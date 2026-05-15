#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${ROOT_DIR}/.tools/node-v24.15.0-linux-x64/bin"
PATH="${NODE_BIN}:${PATH}"
LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-gcforms-localstack}"
LAMBDA_LOCAL_AWS_ENDPOINT="${LAMBDA_LOCAL_AWS_ENDPOINT:-http://gcforms-localstack:4566}"
LAMBDA_DATABASE_URL="${LAMBDA_DATABASE_URL:-postgres://localstack_postgres:chummy@gcforms-postgres:5432/forms?connect_timeout=30&pool_timeout=30}"

aws_local() {
  if [[ "${LOCALSTACK_INSIDE_CONTAINER:-false}" == "true" ]]; then
    awslocal "$@"
  else
    docker exec "$LOCALSTACK_CONTAINER" awslocal "$@"
  fi
}

copy_to_localstack() {
  local source_path="$1"
  local target_path="$2"

  if [[ "${LOCALSTACK_INSIDE_CONTAINER:-false}" == "true" ]]; then
    if [[ "$source_path" != "$target_path" ]]; then
      cp "$source_path" "$target_path"
    fi
  else
    docker cp "$source_path" "$LOCALSTACK_CONTAINER:$target_path"
  fi
}

ensure_lambda_role() {
  local role_policy
  role_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

  aws_local iam create-role \
    --role-name lambda-role \
    --assume-role-policy-document "${role_policy}" >/dev/null 2>&1 || true
}

deploy_submission_lambda() {
  local lambda_dir="${ROOT_DIR}/forms-terraform/lambda-code/submission"
  local archive="/tmp/submission-lambda.zip"

  (
    cd "${lambda_dir}"
    if [[ "${SKIP_LAMBDA_BUILD:-false}" != "true" ]]; then
      node .yarn/releases/yarn-4.10.3.cjs install
      node .yarn/releases/yarn-4.10.3.cjs build
    fi
    rm -f "${archive}"
    bsdtar -a -cf "${archive}" build node_modules package.json
  )

  copy_to_localstack "${archive}" /tmp/submission-lambda.zip

  local environment
  environment="Variables={REGION=ca-central-1,AWS_REGION=ca-central-1,AWS_DEFAULT_REGION=ca-central-1,AWS_ACCESS_KEY_ID=test,AWS_SECRET_ACCESS_KEY=test,LOCAL_AWS_ENDPOINT=${LAMBDA_LOCAL_AWS_ENDPOINT},SQS_URL=${LAMBDA_LOCAL_AWS_ENDPOINT}/000000000000/reliability_queue,S3_RELIABILITY_FILE_STORAGE_BUCKET_NAME=forms-local-reliability-file-storage}"

  if aws_local lambda get-function --function-name Submission >/dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name Submission \
      --zip-file fileb:///tmp/submission-lambda.zip >/dev/null
    aws_local lambda update-function-configuration \
      --function-name Submission \
      --runtime nodejs22.x \
      --handler build/main.handler \
      --environment "$environment" >/dev/null
  else
    aws_local lambda create-function \
      --function-name Submission \
      --runtime nodejs22.x \
      --handler build/main.handler \
      --role arn:aws:iam::000000000000:role/lambda-role \
      --zip-file fileb:///tmp/submission-lambda.zip \
      --environment "$environment" >/dev/null
  fi

  aws_local lambda wait function-active-v2 --function-name Submission
}

deploy_reliability_lambda() {
  local lambda_dir="${ROOT_DIR}/forms-terraform/lambda-code/reliability"
  local archive="/tmp/reliability-lambda.zip"

  (
    cd "${lambda_dir}"
    if [[ "${SKIP_LAMBDA_BUILD:-false}" != "true" ]]; then
      YARN_ENABLE_IMMUTABLE_INSTALLS=false node .yarn/releases/yarn-4.10.3.cjs install
      node .yarn/releases/yarn-4.10.3.cjs build
    fi
    rm -f "${archive}"
    bsdtar -a -cf "${archive}" \
      --exclude 'node_modules/@gcforms' \
      --exclude 'node_modules/@prisma' \
      --exclude 'node_modules/recheck' \
      --exclude 'node_modules/recheck-*' \
      --exclude 'node_modules/@rolldown' \
      --exclude 'node_modules/typescript' \
      --exclude 'node_modules/@types' \
      --exclude 'node_modules/@babel' \
      --exclude 'node_modules/axios' \
      --exclude 'node_modules/@aws-sdk/client-secrets-manager' \
      --exclude 'node_modules/@aws-sdk/client-lambda' \
      --exclude 'node_modules/@aws-sdk/client-sqs' \
      build node_modules package.json
  )

  copy_to_localstack "${archive}" /tmp/reliability-lambda.zip

  local environment
  environment="Variables={REGION=ca-central-1,AWS_REGION=ca-central-1,AWS_DEFAULT_REGION=ca-central-1,AWS_ACCESS_KEY_ID=test,AWS_SECRET_ACCESS_KEY=test,LOCAL_AWS_ENDPOINT=${LAMBDA_LOCAL_AWS_ENDPOINT},DATABASE_URL=${LAMBDA_DATABASE_URL},ENVIRONMENT=local,LOCAL_SKIP_TEMPLATE_DB_LOOKUP=true,LOCAL_SKIP_NOTIFY=true,NOTIFY_API_KEY=local-notify-api-key,TEMPLATE_ID=local-template}"

  if aws_local lambda get-function --function-name Reliability >/dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name Reliability \
      --zip-file fileb:///tmp/reliability-lambda.zip >/dev/null
    aws_local lambda update-function-configuration \
      --function-name Reliability \
      --runtime nodejs22.x \
      --handler build/main.handler \
      --timeout 30 \
      --memory-size 512 \
      --environment "$environment" >/dev/null
  else
    aws_local lambda create-function \
      --function-name Reliability \
      --runtime nodejs22.x \
      --handler build/main.handler \
      --role arn:aws:iam::000000000000:role/lambda-role \
      --timeout 30 \
      --memory-size 512 \
      --zip-file fileb:///tmp/reliability-lambda.zip \
      --environment "$environment" >/dev/null
  fi

  aws_local lambda wait function-active-v2 --function-name Reliability
}

ensure_reliability_event_source() {
  local queue_arn
  local mapping_uuid

  queue_arn="$(
    aws_local sqs get-queue-attributes \
      --queue-url http://localhost:4566/000000000000/reliability_queue \
      --attribute-names QueueArn \
      --query 'Attributes.QueueArn' \
      --output text
  )"

  mapping_uuid="$(
    aws_local lambda list-event-source-mappings \
      --function-name Reliability \
      --event-source-arn "${queue_arn}" \
      --query 'EventSourceMappings[0].UUID' \
      --output text
  )"

  if [[ "${mapping_uuid}" == "None" ]]; then
    aws_local lambda create-event-source-mapping \
      --function-name Reliability \
      --event-source-arn "${queue_arn}" \
      --batch-size 10 \
      --enabled >/dev/null
  fi
}

ensure_lambda_role
deploy_submission_lambda
deploy_reliability_lambda
ensure_reliability_event_source

echo "Local GCForms Lambdas are deployed."

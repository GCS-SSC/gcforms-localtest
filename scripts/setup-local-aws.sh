#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ca-central-1}"
LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-gcforms-localstack}"

aws_local() {
  if [[ "${LOCALSTACK_INSIDE_CONTAINER:-false}" == "true" ]]; then
    AWS_ACCESS_KEY_ID=test \
      AWS_SECRET_ACCESS_KEY=test \
      AWS_DEFAULT_REGION="$REGION" \
      awslocal "$@"
  else
    docker exec \
      -e AWS_ACCESS_KEY_ID=test \
      -e AWS_SECRET_ACCESS_KEY=test \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$LOCALSTACK_CONTAINER" awslocal "$@"
  fi
}

wait_for_localstack() {
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:4566/_localstack/health" >/dev/null; then
      return 0
    fi
    sleep 2
  done

  echo "LocalStack did not become healthy in time" >&2
  return 1
}

create_queue() {
  local name="$1"
  shift || true

  aws_local sqs get-queue-url --queue-name "$name" >/dev/null 2>&1 ||
    aws_local sqs create-queue --queue-name "$name" "$@" >/dev/null
}

create_bucket() {
  local name="$1"

  aws_local s3api head-bucket --bucket "$name" >/dev/null 2>&1 ||
    aws_local s3api create-bucket \
      --bucket "$name" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
}

create_table() {
  local name="$1"
  shift

  aws_local dynamodb describe-table --table-name "$name" >/dev/null 2>&1 ||
    aws_local dynamodb create-table --table-name "$name" "$@" >/dev/null
}

wait_for_table() {
  aws_local dynamodb wait table-exists --table-name "$1"
}

wait_for_localstack

create_queue audit_log_queue
create_queue api_audit_log_queue
create_queue notification_queue
create_queue reliability_queue
create_queue reliability_reprocessing_queue
create_queue file_upload_queue

create_bucket forms-local-vault-file-storage
create_bucket forms-local-reliability-file-storage

create_table ReliabilityQueue \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=SubmissionID,AttributeType=S \
    AttributeName=HasFileKeys,AttributeType=N \
    AttributeName=CreatedAt,AttributeType=N \
  --key-schema AttributeName=SubmissionID,KeyType=HASH \
  --global-secondary-indexes '[{"IndexName":"HasFileKeysByCreatedAt","KeySchema":[{"AttributeName":"HasFileKeys","KeyType":"HASH"},{"AttributeName":"CreatedAt","KeyType":"RANGE"}],"Projection":{"ProjectionType":"INCLUDE","NonKeyAttributes":["SubmissionID","SendReceipt","NotifyProcessed","FileKeys"]}}]'

create_table Vault \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=FormID,AttributeType=S \
    AttributeName=NAME_OR_CONF,AttributeType=S \
    'AttributeName=Status#CreatedAt,AttributeType=S' \
  --key-schema AttributeName=FormID,KeyType=HASH AttributeName=NAME_OR_CONF,KeyType=RANGE \
  --global-secondary-indexes '[{"IndexName":"StatusCreatedAt","KeySchema":[{"AttributeName":"FormID","KeyType":"HASH"},{"AttributeName":"Status#CreatedAt","KeyType":"RANGE"}],"Projection":{"ProjectionType":"INCLUDE","NonKeyAttributes":["CreatedAt","Name"]}}]'

create_table AuditLogs \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=UserID,AttributeType=S \
    'AttributeName=Event#SubjectID#TimeStamp,AttributeType=S' \
    AttributeName=TimeStamp,AttributeType=N \
    AttributeName=Status,AttributeType=S \
    AttributeName=Subject,AttributeType=S \
  --key-schema AttributeName=UserID,KeyType=HASH 'AttributeName=Event#SubjectID#TimeStamp,KeyType=RANGE' \
  --global-secondary-indexes '[{"IndexName":"UserByTime","KeySchema":[{"AttributeName":"UserID","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"KEYS_ONLY"}},{"IndexName":"StatusByTimestamp","KeySchema":[{"AttributeName":"Status","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}},{"IndexName":"SubjectByTimestamp","KeySchema":[{"AttributeName":"Subject","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"KEYS_ONLY"}}]'

create_table ApiAuditLogs \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=UserID,AttributeType=S \
    'AttributeName=Event#SubjectID#TimeStamp,AttributeType=S' \
    AttributeName=TimeStamp,AttributeType=N \
    AttributeName=Status,AttributeType=S \
    AttributeName=Subject,AttributeType=S \
  --key-schema AttributeName=UserID,KeyType=HASH 'AttributeName=Event#SubjectID#TimeStamp,KeyType=RANGE' \
  --global-secondary-indexes '[{"IndexName":"UserByTime","KeySchema":[{"AttributeName":"UserID","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"KEYS_ONLY"}},{"IndexName":"StatusByTimestamp","KeySchema":[{"AttributeName":"Status","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}},{"IndexName":"SubjectByTimestamp","KeySchema":[{"AttributeName":"Subject","KeyType":"HASH"},{"AttributeName":"TimeStamp","KeyType":"RANGE"}],"Projection":{"ProjectionType":"KEYS_ONLY"}}]'

create_table Notification \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=NotificationID,AttributeType=S \
  --key-schema AttributeName=NotificationID,KeyType=HASH

wait_for_table ReliabilityQueue
wait_for_table Vault
wait_for_table AuditLogs
wait_for_table ApiAuditLogs
wait_for_table Notification

echo "Local AWS resources are ready."

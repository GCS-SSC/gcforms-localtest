#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${GC_FORMS_ROOT:-/opt/gcforms}"
POSTGRES_DATA="${POSTGRES_DATA:-/data/postgres}"
REDIS_DATA="${REDIS_DATA:-/data/redis}"
LOCALSTACK_DATA="${LOCALSTACK_VOLUME_DIR:-/data/localstack}"

mkdir -p "$POSTGRES_DATA" "$REDIS_DATA" "$LOCALSTACK_DATA" /data/local-secrets /run/gcforms /var/log/supervisor
chown -R postgres:postgres "$POSTGRES_DATA"
chown -R redis:redis "$REDIS_DATA" || true
chmod 700 "$POSTGRES_DATA" /data/local-secrets

POSTGRES_BINDIR="$(pg_config --bindir)"

if [[ ! -s "${POSTGRES_DATA}/PG_VERSION" ]]; then
  gosu postgres "${POSTGRES_BINDIR}/initdb" -D "$POSTGRES_DATA" -A trust
  {
    echo "host all all 0.0.0.0/0 trust"
    echo "host all all ::/0 trust"
  } >>"${POSTGRES_DATA}/pg_hba.conf"
fi

rm -f /run/gcforms/bootstrap.done

export PATH="${ROOT_DIR}/.tools/node-v24.15.0-linux-x64/bin:/opt/code/localstack/.venv/bin:${PATH}"
export LOCALSTACK_VOLUME_DIR="$LOCALSTACK_DATA"
export SERVICES="${SERVICES:-s3,sqs,dynamodb,lambda,logs,iam,sts}"
export DEFAULT_REGION="${DEFAULT_REGION:-ca-central-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ca-central-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT="${LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT:-60}"
export LAMBDA_SYNCHRONOUS_CREATE="${LAMBDA_SYNCHRONOUS_CREATE:-1}"
export LAMBDA_IGNORE_ARCHITECTURE="${LAMBDA_IGNORE_ARCHITECTURE:-1}"
export DEBUG="${DEBUG:-0}"

exec /usr/bin/supervisord -c "${ROOT_DIR}/omnibus/supervisord.conf"

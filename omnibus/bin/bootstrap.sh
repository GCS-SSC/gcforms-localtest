#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${GC_FORMS_ROOT:-/opt/gcforms}"
PATH="${ROOT_DIR}/.tools/node-v24.15.0-linux-x64/bin:/opt/code/localstack/.venv/bin:${PATH}"
CONTAINER_HOST="${GC_FORMS_CONTAINER_HOST:-$(hostname -i | awk '{print $1}')}"

"${ROOT_DIR}/omnibus/bin/write-env.sh"

for _ in $(seq 1 120); do
  if pg_isready -h 127.0.0.1 -p 5432 -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

psql -h 127.0.0.1 -p 5432 -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = 'localstack_postgres'" | grep -q 1 ||
  psql -h 127.0.0.1 -p 5432 -U postgres -c "CREATE ROLE localstack_postgres LOGIN PASSWORD 'chummy' CREATEDB"

psql -h 127.0.0.1 -p 5432 -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'forms'" | grep -q 1 ||
  createdb -h 127.0.0.1 -p 5432 -U postgres -O localstack_postgres forms

for _ in $(seq 1 120); do
  if redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:4566/_localstack/health" >/dev/null; then
    break
  fi
  sleep 1
done

(
  cd "${ROOT_DIR}/platform-forms-client"
  node .yarn/releases/yarn-4.14.0.cjs db:generate
  node .yarn/releases/yarn-4.14.0.cjs db:dev
)

LOCALSTACK_INSIDE_CONTAINER=true "${ROOT_DIR}/scripts/setup-local-aws.sh"
POSTGRES_INSIDE_CONTAINER=true LOCAL_SECRETS_DIR=/data/local-secrets "${ROOT_DIR}/scripts/seed-local-data.sh"

LOCALSTACK_INSIDE_CONTAINER=true \
  SKIP_LAMBDA_BUILD=true \
  LAMBDA_LOCAL_AWS_ENDPOINT="http://${CONTAINER_HOST}:4566" \
  LAMBDA_DATABASE_URL="postgres://localstack_postgres:chummy@${CONTAINER_HOST}:5432/forms?connect_timeout=30&pool_timeout=30" \
  "${ROOT_DIR}/scripts/deploy-local-lambdas.sh"

LOCALSTACK_INSIDE_CONTAINER=true "${ROOT_DIR}/scripts/seed-local-submissions.sh"

touch /run/gcforms/bootstrap.done
echo "GCForms omnibus bootstrap complete."

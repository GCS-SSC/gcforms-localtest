#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ca-central-1}"
LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-gcforms-localstack}"
SMOKE_FORM_ID="${SMOKE_FORM_ID:-clg17xha50008efkgfgxa8l4f}"
SECOND_FORM_ID="${SECOND_FORM_ID:-clocalapi0000000000000000}"
CLAIMS_FORM_ID="${CLAIMS_FORM_ID:-clocalclaims0000000000000}"
SEED_STATE_DIR="${SEED_STATE_DIR:-${LOCAL_SECRETS_DIR:-/data/local-secrets}}"
CLAIMS_SUBMISSION_MARKER="${CLAIMS_SUBMISSION_MARKER:-${SEED_STATE_DIR}/claims-submissions-v3.seeded}"

mkdir -p "$(dirname "$CLAIMS_SUBMISSION_MARKER")" 2>/dev/null || true

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

vault_submission_count() {
  local form_id="$1"

  aws_local dynamodb query \
    --table-name Vault \
    --key-condition-expression 'FormID = :formId AND begins_with(NAME_OR_CONF, :prefix)' \
    --expression-attribute-values "{\":formId\":{\"S\":\"${form_id}\"},\":prefix\":{\"S\":\"NAME#\"}}" \
    --select COUNT \
    --query Count \
    --output text
}

invoke_submission() {
  local form_id="$1"
  local payload="$2"
  local output="/tmp/gcforms-seed-${form_id}.json"

  aws_local lambda invoke \
    --function-name Submission \
    --payload "$payload" \
    "$output" >/dev/null
}

invoke_claims_submission() {
  local agreement_number="$1"
  local fiscal_year="$2"
  local start_month="$3"
  local end_month="$4"
  local equipment_amount="$5"
  local travel_amount="$6"
  local notes="$7"
  local payload

  payload="$(cat <<JSON
{"formID":"${CLAIMS_FORM_ID}","language":"en","securityAttribute":"Protected A","responses":{"agreement_number":"${agreement_number}","fiscal_year":"${fiscal_year}","claim_period_start_month":"${start_month}","claim_period_end_month":"${end_month}","submitted_line_items":[{"submitted_item":"Operating Costs -> Administration -> Equipment","submitted_amount":"${equipment_amount}"},{"submitted_item":"Operating Costs -> Delivery -> Travel","submitted_amount":"${travel_amount}"}],"claim_notes":"${notes}"}}
JSON
)"

  invoke_submission "$CLAIMS_FORM_ID" "$payload"
}

wait_for_vault_submission() {
  local form_id="$1"
  local min_count="${2:-1}"

  for _ in $(seq 1 30); do
    if [[ "$(vault_submission_count "$form_id")" -ge "$min_count" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for a Vault submission for ${form_id}" >&2
  return 1
}

if [[ "$(vault_submission_count "$SMOKE_FORM_ID")" -eq 0 ]]; then
  invoke_submission "$SMOKE_FORM_ID" "{\"formID\":\"${SMOKE_FORM_ID}\",\"language\":\"en\",\"securityAttribute\":\"Protected A\",\"responses\":{\"1\":\"Seeded API User\",\"2\":\"Numero Uno\",\"3\":[\"Uno\"],\"4\":\"List item 1\",\"5\":\"Seeded local API response\",\"6\":\"613-555-0100\",\"7\":\"seeded@example.test\",\"8\":\"05/15/2026\",\"9\":\"1\"}}"
  wait_for_vault_submission "$SMOKE_FORM_ID"
fi

if [[ "$(vault_submission_count "$SECOND_FORM_ID")" -eq 0 ]]; then
  invoke_submission "$SECOND_FORM_ID" "{\"formID\":\"${SECOND_FORM_ID}\",\"language\":\"en\",\"securityAttribute\":\"Protected A\",\"responses\":{\"1\":\"Lemonade Stand\",\"2\":\"Seeded local API submission\",\"3\":\"seeded@example.test\"}}"
  wait_for_vault_submission "$SECOND_FORM_ID"
fi

claims_submission_count="$(vault_submission_count "$CLAIMS_FORM_ID")"
if [[ "$claims_submission_count" -lt 3 || ! -f "$CLAIMS_SUBMISSION_MARKER" ]]; then
  invoke_claims_submission "AGR-0001" "2025-2026" "April" "June" "10.00" "25.00" \
    "Seeded claim 1 for GCS agreement 51 claim integration testing."
  invoke_claims_submission "AGR-0001" "2025-2026" "July" "September" "20.00" "50.00" \
    "Seeded claim 2 for GCS agreement 51 claim integration testing."
  invoke_claims_submission "AGR-0001" "2026-2027" "October" "March" "30.00" "75.00" \
    "Seeded claim 3 for GCS agreement 51 claim integration testing."
  wait_for_vault_submission "$CLAIMS_FORM_ID" "$((claims_submission_count + 3))"
  touch "$CLAIMS_SUBMISSION_MARKER" 2>/dev/null || true
fi

echo "Local sample submissions are ready."

#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ca-central-1}"
LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-gcforms-localstack}"
SMOKE_FORM_ID="${SMOKE_FORM_ID:-clg17xha50008efkgfgxa8l4f}"
SECOND_FORM_ID="${SECOND_FORM_ID:-clocalapi0000000000000000}"
CLAIMS_FORM_ID="${CLAIMS_FORM_ID:-clocalclaims0000000000000}"

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

wait_for_vault_submission() {
  local form_id="$1"

  for _ in $(seq 1 30); do
    if [[ "$(vault_submission_count "$form_id")" -gt 0 ]]; then
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

if [[ "$(vault_submission_count "$CLAIMS_FORM_ID")" -eq 0 ]]; then
  invoke_submission "$CLAIMS_FORM_ID" "{\"formID\":\"${CLAIMS_FORM_ID}\",\"language\":\"en\",\"securityAttribute\":\"Protected A\",\"responses\":{\"agreement_number\":\"AGR-0001\",\"agreement_title\":\"Health Canada Core Agreement 1\",\"claim_name\":\"Claim 1\",\"fiscal_year\":\"2025-2026\",\"claim_period\":\"Apr-Jun\",\"equipment_submitted_amount\":\"10.00\",\"travel_submitted_amount\":\"25.00\",\"total_submitted_amount\":\"35.00\",\"claim_external_reference\":\"AGR-0001/Claim 1\",\"claim_notes\":\"Seeded local submission matching the GCS-SSC Claim 1 test screen.\"}}"
  wait_for_vault_submission "$CLAIMS_FORM_ID"
fi

echo "Local sample submissions are ready."

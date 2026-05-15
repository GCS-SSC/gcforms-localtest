#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-gcforms-postgres}"
LOCAL_SECRETS_DIR="${LOCAL_SECRETS_DIR:-${ROOT_DIR}/local-secrets}"
SMOKE_FORM_ID="${SMOKE_FORM_ID:-clg17xha50008efkgfgxa8l4f}"
SECOND_FORM_ID="${SECOND_FORM_ID:-clocalapi0000000000000000}"

mkdir -p "$LOCAL_SECRETS_DIR"
chmod 700 "$LOCAL_SECRETS_DIR"

psql_forms() {
  if [[ "${POSTGRES_INSIDE_CONTAINER:-false}" == "true" ]]; then
    PGPASSWORD="${POSTGRES_PASSWORD:-chummy}" psql \
      -h "${POSTGRES_HOST:-127.0.0.1}" \
      -p "${POSTGRES_PORT:-5432}" \
      -U "${POSTGRES_USER:-localstack_postgres}" \
      -d "${POSTGRES_DB:-forms}" \
      "$@"
  else
    docker exec -i "$POSTGRES_CONTAINER" psql \
      -U "${POSTGRES_USER:-localstack_postgres}" \
      -d "${POSTGRES_DB:-forms}" \
      "$@"
  fi
}

create_key_pair() {
  local name="$1"
  local private_key="${LOCAL_SECRETS_DIR}/${name}-private.pem"
  local public_key="${LOCAL_SECRETS_DIR}/${name}-public.pem"

  if [[ ! -f "$private_key" ]]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$private_key" >/dev/null 2>&1
    chmod 600 "$private_key"
  fi

  openssl rsa -pubout -in "$private_key" -out "$public_key" >/dev/null 2>&1
  chmod 644 "$public_key"
}

public_key_sql_literal() {
  local name="$1"
  sed ':a;N;$!ba;s/\n/\\n/g' "${LOCAL_SECRETS_DIR}/${name}-public.pem"
}

create_key_pair local-service-account
create_key_pair local-second-service-account

PUBLIC_KEY_1="$(public_key_sql_literal local-service-account)"
PUBLIC_KEY_2="$(public_key_sql_literal local-second-service-account)"

psql_forms <<SQL
DO \$\$
DECLARE
  security_question_ids text[];
  smoke_form_id text := '${SMOKE_FORM_ID}';
  second_form_id text := '${SECOND_FORM_ID}';
BEGIN
  SELECT array_agg(id ORDER BY id) INTO security_question_ids FROM "SecurityQuestion";

  INSERT INTO "User" (id, email, name, active, "emailVerified")
  VALUES
    ('local-admin-user', 'local.admin@cds-snc.ca', 'Local Admin', true, now()),
    ('local-manager-user', 'local.manager@cds-snc.ca', 'Local Manager', true, now()),
    ('local-builder-user', 'local.builder@cds-snc.ca', 'Local Builder', true, now()),
    ('local-viewer-user', 'local.viewer@cds-snc.ca', 'Local Viewer', true, now()),
    ('local-inactive-user', 'local.inactive@cds-snc.ca', 'Local Inactive User', false, now())
  ON CONFLICT (email) DO UPDATE SET
    name = EXCLUDED.name,
    active = EXCLUDED.active,
    "emailVerified" = EXCLUDED."emailVerified";

  INSERT INTO "_PrivilegeToUser" ("A", "B")
  SELECT p.id, u.id
  FROM "Privilege" p
  JOIN "User" u ON u.email IN ('local.admin@cds-snc.ca', 'local.manager@cds-snc.ca')
  WHERE p.name IN ('Base', 'PublishForms', 'ManageApplicationSettings', 'ManageUsers', 'ManageForms')
  ON CONFLICT DO NOTHING;

  INSERT INTO "_PrivilegeToUser" ("A", "B")
  SELECT p.id, u.id
  FROM "Privilege" p
  JOIN "User" u ON u.email = 'local.builder@cds-snc.ca'
  WHERE p.name IN ('Base', 'PublishForms', 'ManageForms')
  ON CONFLICT DO NOTHING;

  INSERT INTO "_PrivilegeToUser" ("A", "B")
  SELECT p.id, u.id
  FROM "Privilege" p
  JOIN "User" u ON u.email IN ('local.viewer@cds-snc.ca', 'local.inactive@cds-snc.ca')
  WHERE p.name IN ('Base')
  ON CONFLICT DO NOTHING;

  IF array_length(security_question_ids, 1) >= 3 THEN
    INSERT INTO "SecurityAnswer" (id, answer, "userId", "securityQuestionId")
    SELECT
      'local-security-answer-' || u.id || '-' || sq.id,
      'example-answer',
      u.id,
      sq.id
    FROM "User" u
    CROSS JOIN unnest(security_question_ids[1:3]) AS sq(id)
    WHERE u.email IN (
      'local.admin@cds-snc.ca',
      'local.manager@cds-snc.ca',
      'local.builder@cds-snc.ca',
      'local.viewer@cds-snc.ca',
      'local.inactive@cds-snc.ca'
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;

  INSERT INTO "Template" (
    id, "jsonConfig", "isPublished", created_at, updated_at, name,
    "securityAttribute", "formPurpose", "publishReason", "publishFormType", "publishDesc", "saveAndResume"
  )
  SELECT
    smoke_form_id, "jsonConfig", true, now(), now(), 'Local published GCForms smoke test',
    'Protected A', 'Local testing', 'Local testing', 'Other', 'Local published form for self-hosted smoke tests', true
  FROM "Template"
  WHERE id = '2'
  ON CONFLICT (id) DO UPDATE SET
    "jsonConfig" = EXCLUDED."jsonConfig",
    "isPublished" = true,
    updated_at = now(),
    name = EXCLUDED.name,
    "formPurpose" = EXCLUDED."formPurpose",
    "publishReason" = EXCLUDED."publishReason",
    "publishFormType" = EXCLUDED."publishFormType",
    "publishDesc" = EXCLUDED."publishDesc";

  INSERT INTO "Template" (
    id, "jsonConfig", "isPublished", created_at, updated_at, name,
    "securityAttribute", "formPurpose", "publishReason", "publishFormType", "publishDesc", "saveAndResume"
  )
  SELECT
    second_form_id, "jsonConfig", true, now(), now(), 'Local API integration test form',
    'Protected A', 'Local API testing', 'Local testing', 'Other', 'Second local form for API integration tests', true
  FROM "Template"
  WHERE id = '1'
  ON CONFLICT (id) DO UPDATE SET
    "jsonConfig" = EXCLUDED."jsonConfig",
    "isPublished" = true,
    updated_at = now(),
    name = EXCLUDED.name,
    "formPurpose" = EXCLUDED."formPurpose",
    "publishReason" = EXCLUDED."publishReason",
    "publishFormType" = EXCLUDED."publishFormType",
    "publishDesc" = EXCLUDED."publishDesc";

  INSERT INTO "_TemplateToUser" ("A", "B")
  SELECT template_id, u.id
  FROM (VALUES (smoke_form_id), (second_form_id)) AS forms(template_id)
  JOIN "User" u ON u.email IN ('local.admin@cds-snc.ca', 'local.manager@cds-snc.ca', 'local.builder@cds-snc.ca')
  ON CONFLICT DO NOTHING;
END
\$\$;

INSERT INTO "ApiServiceAccount" (id, created_at, updated_at, "templateId", "publicKeyId", "publicKey")
VALUES (
  'local-service-account',
  now(),
  now(),
  '${SMOKE_FORM_ID}',
  'local-service-account-public-key',
  E'${PUBLIC_KEY_1}'
)
ON CONFLICT (id) DO UPDATE SET
  updated_at = now(),
  "templateId" = EXCLUDED."templateId",
  "publicKeyId" = EXCLUDED."publicKeyId",
  "publicKey" = EXCLUDED."publicKey";

INSERT INTO "ApiServiceAccount" (id, created_at, updated_at, "templateId", "publicKeyId", "publicKey")
VALUES (
  'local-second-service-account',
  now(),
  now(),
  '${SECOND_FORM_ID}',
  'local-second-service-account-public-key',
  E'${PUBLIC_KEY_2}'
)
ON CONFLICT (id) DO UPDATE SET
  updated_at = now(),
  "templateId" = EXCLUDED."templateId",
  "publicKeyId" = EXCLUDED."publicKeyId",
  "publicKey" = EXCLUDED."publicKey";
SQL

cat <<EOF
Local seed data is ready.

Users:
  local.admin@cds-snc.ca
  local.manager@cds-snc.ca
  local.builder@cds-snc.ca
  local.viewer@cds-snc.ca
  local.inactive@cds-snc.ca

API forms:
  ${SMOKE_FORM_ID} -> token local:${SMOKE_FORM_ID}:local-service-account
  ${SECOND_FORM_ID} -> token local:${SECOND_FORM_ID}:local-second-service-account

Private keys:
  ${LOCAL_SECRETS_DIR}/local-service-account-private.pem
  ${LOCAL_SECRETS_DIR}/local-second-service-account-private.pem
EOF

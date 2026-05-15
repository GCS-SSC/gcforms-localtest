#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-gcforms-postgres}"
LOCAL_SECRETS_DIR="${LOCAL_SECRETS_DIR:-${ROOT_DIR}/local-secrets}"
SMOKE_FORM_ID="${SMOKE_FORM_ID:-clg17xha50008efkgfgxa8l4f}"
SECOND_FORM_ID="${SECOND_FORM_ID:-clocalapi0000000000000000}"
CLAIMS_FORM_ID="${CLAIMS_FORM_ID:-clocalclaims0000000000000}"
SMOKE_CREDENTIAL_ID="${SMOKE_CREDENTIAL_ID:-local-smoke-gcforms}"
SECOND_CREDENTIAL_ID="${SECOND_CREDENTIAL_ID:-local-second-gcforms}"
CLAIMS_CREDENTIAL_ID="${CLAIMS_CREDENTIAL_ID:-local-claims-gcforms}"

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

private_key_json_literal() {
  local name="$1"
  sed ':a;N;$!ba;s/\n/\\n/g' "${LOCAL_SECRETS_DIR}/${name}-private.pem"
}

public_key_json_literal() {
  local name="$1"
  sed ':a;N;$!ba;s/\n/\\n/g' "${LOCAL_SECRETS_DIR}/${name}-public.pem"
}

create_key_pair local-service-account
create_key_pair local-second-service-account
create_key_pair local-claims-service-account
create_key_pair local-zitadel-admin

PUBLIC_KEY_1="$(public_key_sql_literal local-service-account)"
PUBLIC_KEY_2="$(public_key_sql_literal local-second-service-account)"
PUBLIC_KEY_3="$(public_key_sql_literal local-claims-service-account)"

psql_forms <<SQL
DO \$\$
DECLARE
  security_question_ids text[];
  smoke_form_id text := '${SMOKE_FORM_ID}';
  second_form_id text := '${SECOND_FORM_ID}';
  claims_form_id text := '${CLAIMS_FORM_ID}';
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

  INSERT INTO "Template" (
    id, "jsonConfig", "isPublished", created_at, updated_at, name,
    "securityAttribute", "formPurpose", "publishReason", "publishFormType", "publishDesc", "saveAndResume"
  )
  VALUES (
    claims_form_id,
    \$json\$
    {
      "titleEn": "GCS claim submission integration test",
      "titleFr": "Test d integration des demandes GCS",
      "introduction": {
        "descriptionEn": "Local-only test form for GCS claim submission integration.",
        "descriptionFr": "Formulaire de test local pour l integration des demandes GCS."
      },
      "privacyPolicy": {
        "descriptionEn": "Use test data only. This local form is not connected to production GCForms.",
        "descriptionFr": "Utilisez seulement des donnees de test. Ce formulaire local n est pas connecte a GCForms en production."
      },
      "confirmation": {
        "descriptionEn": "Your local test claim submission was received.",
        "descriptionFr": "Votre soumission locale de test a ete recue.",
        "referrerUrlEn": "",
        "referrerUrlFr": ""
      },
      "layout": [1, 2, 3, 4, 5, 6],
      "elements": [
        {
          "id": 1,
          "type": "textField",
          "properties": {
            "questionId": "agreement_number",
            "tags": ["gcs", "claim", "agreement"],
            "subElements": [],
            "choices": [{ "en": "", "fr": "" }],
            "titleEn": "Agreement number",
            "titleFr": "Numero d accord",
            "validation": { "required": true },
            "descriptionEn": "",
            "descriptionFr": "",
            "placeholderEn": "AGR-0001",
            "placeholderFr": "AGR-0001"
          },
          "uuid": "00000000-0000-4000-8000-000000000001"
        },
        {
          "id": 2,
          "type": "dropdown",
          "properties": {
            "questionId": "fiscal_year",
            "tags": ["gcs", "claim", "agreement-51"],
            "subElements": [],
            "choices": [
              { "en": "", "fr": "" },
              { "en": "2025-2026", "fr": "2025-2026" },
              { "en": "2026-2027", "fr": "2026-2027" }
            ],
            "titleEn": "Fiscal year",
            "titleFr": "Exercice financier",
            "validation": { "required": true },
            "descriptionEn": "Limited to fiscal years seeded for the agency that owns GCS agreement 51.",
            "descriptionFr": "Limite aux exercices financiers initialises pour l organisation de l accord GCS 51.",
            "placeholderEn": "",
            "placeholderFr": ""
          },
          "uuid": "00000000-0000-4000-8000-000000000002"
        },
        {
          "id": 3,
          "type": "dropdown",
          "properties": {
            "questionId": "claim_period_start_month",
            "tags": ["gcs", "claim"],
            "subElements": [],
            "choices": [
              { "en": "", "fr": "" },
              { "en": "April", "fr": "Avril" },
              { "en": "May", "fr": "Mai" },
              { "en": "June", "fr": "Juin" },
              { "en": "July", "fr": "Juillet" },
              { "en": "August", "fr": "Aout" },
              { "en": "September", "fr": "Septembre" },
              { "en": "October", "fr": "Octobre" },
              { "en": "November", "fr": "Novembre" },
              { "en": "December", "fr": "Decembre" },
              { "en": "January", "fr": "Janvier" },
              { "en": "February", "fr": "Fevrier" },
              { "en": "March", "fr": "Mars" }
            ],
            "titleEn": "Claim period start month",
            "titleFr": "Mois de debut de la periode de demande",
            "validation": { "required": true },
            "descriptionEn": "GCS stores April as 0 and March as 11.",
            "descriptionFr": "GCS enregistre avril comme 0 et mars comme 11.",
            "placeholderEn": "",
            "placeholderFr": ""
          },
          "uuid": "00000000-0000-4000-8000-000000000003"
        },
        {
          "id": 4,
          "type": "dropdown",
          "properties": {
            "questionId": "claim_period_end_month",
            "tags": ["gcs", "claim"],
            "subElements": [],
            "choices": [
              { "en": "", "fr": "" },
              { "en": "April", "fr": "Avril" },
              { "en": "May", "fr": "Mai" },
              { "en": "June", "fr": "Juin" },
              { "en": "July", "fr": "Juillet" },
              { "en": "August", "fr": "Aout" },
              { "en": "September", "fr": "Septembre" },
              { "en": "October", "fr": "Octobre" },
              { "en": "November", "fr": "Novembre" },
              { "en": "December", "fr": "Decembre" },
              { "en": "January", "fr": "Janvier" },
              { "en": "February", "fr": "Fevrier" },
              { "en": "March", "fr": "Mars" }
            ],
            "titleEn": "Claim period end month",
            "titleFr": "Mois de fin de la periode de demande",
            "validation": { "required": true },
            "descriptionEn": "GCS stores April as 0 and March as 11.",
            "descriptionFr": "GCS enregistre avril comme 0 et mars comme 11.",
            "placeholderEn": "",
            "placeholderFr": ""
          },
          "uuid": "00000000-0000-4000-8000-000000000004"
        },
        {
          "id": 5,
          "type": "dynamicRow",
          "properties": {
            "questionId": "submitted_line_items",
            "tags": ["gcs", "claim", "line_items"],
            "choices": [{ "en": "", "fr": "" }],
            "titleEn": "Submitted claim items",
            "titleFr": "Articles soumis pour la demande",
            "dynamicRow": {
              "rowTitleEn": "Claim item",
              "rowTitleFr": "Article de demande",
              "addButtonTextEn": "Add another item",
              "addButtonTextFr": "Ajouter un autre article",
              "removeButtonTextEn": "Remove item",
              "removeButtonTextFr": "Supprimer l article"
            },
            "validation": { "required": true },
            "descriptionEn": "Select budget items from GCS agreement 51 and enter submitted amounts.",
            "descriptionFr": "Selectionnez les articles budgetaires de l accord GCS 51 et entrez les montants soumis.",
            "subElements": [
              {
                "id": 501,
                "type": "dropdown",
                "properties": {
                  "questionId": "submitted_item",
                  "tags": ["gcs", "claim", "line_item"],
                  "choices": [
                    { "en": "", "fr": "" },
                    {
                      "en": "Operating Costs -> Administration -> Equipment",
                      "fr": "Couts de fonctionnement -> Administration -> Equipement"
                    },
                    {
                      "en": "Operating Costs -> Delivery -> Travel",
                      "fr": "Couts de fonctionnement -> Prestation -> Deplacement"
                    }
                  ],
                  "titleEn": "Submitted item",
                  "titleFr": "Article soumis",
                  "validation": { "required": true },
                  "descriptionEn": "",
                  "descriptionFr": "",
                  "placeholderEn": "",
                  "placeholderFr": ""
                }
              },
              {
                "id": 502,
                "type": "textField",
                "properties": {
                  "questionId": "submitted_amount",
                  "tags": ["gcs", "claim", "line_item", "money"],
                  "choices": [{ "en": "", "fr": "" }],
                  "titleEn": "Submitted amount",
                  "titleFr": "Montant soumis",
                  "validation": { "required": true },
                  "descriptionEn": "Enter a number without a currency symbol.",
                  "descriptionFr": "Entrez un nombre sans symbole de devise.",
                  "placeholderEn": "10.00",
                  "placeholderFr": "10.00"
                }
              }
            ]
          },
          "uuid": "00000000-0000-4000-8000-000000000005"
        },
        {
          "id": 6,
          "type": "textArea",
          "properties": {
            "questionId": "claim_notes",
            "tags": ["gcs", "claim", "notes"],
            "subElements": [],
            "choices": [{ "en": "", "fr": "" }],
            "titleEn": "Claim notes",
            "titleFr": "Notes sur la demande",
            "validation": { "required": false },
            "descriptionEn": "",
            "descriptionFr": "",
            "placeholderEn": "",
            "placeholderFr": ""
          },
          "uuid": "00000000-0000-4000-8000-000000000006"
        }
      ]
    }
    \$json\$::jsonb,
    true,
    now(),
    now(),
    'GCS claim submission integration test',
    'Protected A',
    'Local GCS claim integration testing',
    'Local testing',
    'Other',
    'Local published form for GCS claim API integration tests',
    true
  )
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
  FROM (VALUES (smoke_form_id), (second_form_id), (claims_form_id)) AS forms(template_id)
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

INSERT INTO "ApiServiceAccount" (id, created_at, updated_at, "templateId", "publicKeyId", "publicKey")
VALUES (
  'local-claims-service-account',
  now(),
  now(),
  '${CLAIMS_FORM_ID}',
  'local-claims-service-account-public-key',
  E'${PUBLIC_KEY_3}'
)
ON CONFLICT (id) DO UPDATE SET
  updated_at = now(),
  "templateId" = EXCLUDED."templateId",
  "publicKeyId" = EXCLUDED."publicKeyId",
  "publicKey" = EXCLUDED."publicKey";
SQL

PRIVATE_KEY_1="$(private_key_json_literal local-service-account)"
PRIVATE_KEY_2="$(private_key_json_literal local-second-service-account)"
PRIVATE_KEY_3="$(private_key_json_literal local-claims-service-account)"
PUBLIC_KEY_JSON_1="$(public_key_json_literal local-service-account)"
PUBLIC_KEY_JSON_2="$(public_key_json_literal local-second-service-account)"
PUBLIC_KEY_JSON_3="$(public_key_json_literal local-claims-service-account)"
PUBLIC_KEY_JSON_ADMIN="$(public_key_json_literal local-zitadel-admin)"

cat >"${LOCAL_SECRETS_DIR}/gcforms-api-credentials.json" <<EOF_JSON
{
  "${SMOKE_CREDENTIAL_ID}": {
    "keyId": "local-service-account-public-key",
    "key": "${PRIVATE_KEY_1}",
    "userId": "local-service-account",
    "formId": "${SMOKE_FORM_ID}"
  },
  "${SECOND_CREDENTIAL_ID}": {
    "keyId": "local-second-service-account-public-key",
    "key": "${PRIVATE_KEY_2}",
    "userId": "local-second-service-account",
    "formId": "${SECOND_FORM_ID}"
  },
  "${CLAIMS_CREDENTIAL_ID}": {
    "keyId": "local-claims-service-account-public-key",
    "key": "${PRIVATE_KEY_3}",
    "userId": "local-claims-service-account",
    "formId": "${CLAIMS_FORM_ID}"
  }
}
EOF_JSON
chmod 600 "${LOCAL_SECRETS_DIR}/gcforms-api-credentials.json"

cat >"${LOCAL_SECRETS_DIR}/local-idp-credentials.json" <<EOF_JSON
{
  "local-service-account-public-key": {
    "credentialId": "${SMOKE_CREDENTIAL_ID}",
    "serviceAccountId": "local-service-account",
    "keyId": "local-service-account-public-key",
    "publicKey": "${PUBLIC_KEY_JSON_1}",
    "userId": "local-service-account",
    "formId": "${SMOKE_FORM_ID}"
  },
  "local-second-service-account-public-key": {
    "credentialId": "${SECOND_CREDENTIAL_ID}",
    "serviceAccountId": "local-second-service-account",
    "keyId": "local-second-service-account-public-key",
    "publicKey": "${PUBLIC_KEY_JSON_2}",
    "userId": "local-second-service-account",
    "formId": "${SECOND_FORM_ID}"
  },
  "local-claims-service-account-public-key": {
    "credentialId": "${CLAIMS_CREDENTIAL_ID}",
    "serviceAccountId": "local-claims-service-account",
    "keyId": "local-claims-service-account-public-key",
    "publicKey": "${PUBLIC_KEY_JSON_3}",
    "userId": "local-claims-service-account",
    "formId": "${CLAIMS_FORM_ID}"
  },
  "local-zitadel-admin-public-key": {
    "credentialId": "local-zitadel-admin",
    "serviceAccountId": "local-zitadel-admin",
    "keyId": "local-zitadel-admin-public-key",
    "publicKey": "${PUBLIC_KEY_JSON_ADMIN}",
    "userId": "local-zitadel-admin",
    "formId": "local-zitadel-admin"
  }
}
EOF_JSON
chmod 644 "${LOCAL_SECRETS_DIR}/local-idp-credentials.json"

cat <<EOF
Local seed data is ready.

Users:
  local.admin@cds-snc.ca
  local.manager@cds-snc.ca
  local.builder@cds-snc.ca
  local.viewer@cds-snc.ca
  local.inactive@cds-snc.ca

API forms:
  ${SMOKE_FORM_ID} -> credential ${SMOKE_CREDENTIAL_ID}
  ${SECOND_FORM_ID} -> credential ${SECOND_CREDENTIAL_ID}
  ${CLAIMS_FORM_ID} -> credential ${CLAIMS_CREDENTIAL_ID}

Private keys:
  ${LOCAL_SECRETS_DIR}/local-service-account-private.pem
  ${LOCAL_SECRETS_DIR}/local-second-service-account-private.pem
  ${LOCAL_SECRETS_DIR}/local-claims-service-account-private.pem

Private API key JSON:
  ${LOCAL_SECRETS_DIR}/gcforms-api-credentials.json
EOF

# GCForms Local Test

`gcforms-localtest` packages GCForms, the Forms API, a local GCForms-style
identity provider, LocalStack, Postgres, Redis, seeded users, seeded forms, and
sample submissions into one Docker Compose workflow for local integration tests.

## Not For Production

This repository is only for local development, testing, modelling, and API
integration experiments.

Do not use it for production or real submissions. It uses local web login,
generated local RSA keys, LocalStack instead of AWS, permissive local database
settings, and seeded test data.

## One Command

```bash
docker compose up -d --build --wait
```

When the command returns, the GCForms API health check has passed.

## Local URLs

- GCForms web app: http://localhost:3000
- Forms API: http://localhost:3001/v1
- Local GCForms IDP: http://localhost:8080
- LocalStack AWS APIs: http://localhost:4566
- Postgres: `127.0.0.1:4510`
- Redis: `127.0.0.1:6379`

The IDP implements the same client-facing flow as hosted GCForms for local use:
your client signs a JWT with the private API key, exchanges it at
`/oauth/v2/token`, then calls the Forms API with the returned bearer token.

## Seeded Login

Local login accepts any non-empty password for active seeded users. The MFA code
is always `12345`.

- `local.admin@cds-snc.ca`
- `local.manager@cds-snc.ca`
- `local.builder@cds-snc.ca`
- `local.viewer@cds-snc.ca`

`local.inactive@cds-snc.ca` is seeded but inactive.

## GCS Claims Test Form

Use this form as the first integration point from `../gcs-ssc` and the
`gcs-gcforms-integration` extension.

- Public form: http://localhost:3000/en/id/clocalclaims0000000000000
- Form ID: `clocalclaims0000000000000`
- Credential ID: `local-claims-gcforms`
- Forms API base URL: `http://localhost:3001/v1`
- Identity provider URL: `http://localhost:8080`
- Project identifier: `284778202772022819`
- Private API key file in the container:
  `/data/local-secrets/local-claims-service-account-private.pem`

Print the exact `GCS_GCFORMS_CREDENTIALS_JSON` value for GCS-SSC:

```bash
docker compose exec -T omnibus \
  node /opt/gcforms/scripts/print-local-credential.mjs
```

That command outputs JSON keyed by `local-claims-gcforms`. Use the whole output
as the GCS-SSC environment variable value.

The seeded claims submission contains these GCForms question IDs:

- `agreement_number`: `AGR-0001`
- `agreement_title`: `Health Canada Core Agreement 1`
- `claim_name`: `Claim 1`
- `fiscal_year`: `2025-2026`
- `claim_period`: `Apr-Jun`
- `equipment_submitted_amount`: `10.00`
- `travel_submitted_amount`: `25.00`
- `total_submitted_amount`: `35.00`
- `claim_external_reference`: `AGR-0001/Claim 1`
- `claim_notes`: local test note

Run the decrypting API smoke test against that form:

```bash
docker compose exec -T \
  -e GC_FORMS_FORM_ID=clocalclaims0000000000000 \
  -e GC_FORMS_SERVICE_ACCOUNT_ID=local-claims-service-account \
  omnibus \
  node /opt/gcforms/scripts/api-local-smoke.mjs
```

## GCS-SSC Setup

Do not change GCS-SSC code just to point it at this local GCForms instance.
Configure it the same way you would configure hosted GCForms.

Set this in the GCS-SSC server environment:

```bash
GCS_GCFORMS_CREDENTIALS_JSON='<output from print-local-credential.mjs>'
```

Then configure the extension in GCS-SSC:

- Agency GCForms API base URL: `http://localhost:3001/v1`
- Stream credential ID: `local-claims-gcforms`
- Stream form ID: `clocalclaims0000000000000`
- Stream identity provider URL: `http://localhost:8080`
- Stream project identifier: `284778202772022819`

If GCS-SSC itself runs inside Docker, use host-reachable URLs instead, usually
`http://host.docker.internal:3001/v1` and `http://host.docker.internal:8080`.

Suggested initial mappings:

- `agreement_number` -> `agreement.number` as `string`
- `agreement_title` -> `agreement.title` as `string`
- `claim_name` -> `claim.name` as `string`
- `fiscal_year` -> `claim.fiscalYear` as `string`
- `claim_period` -> `claim.period` as `string`
- `equipment_submitted_amount` -> `claim_line_item.equipment.submittedAmount` as `money`
- `travel_submitted_amount` -> `claim_line_item.travel.submittedAmount` as `money`
- `total_submitted_amount` -> `claim.submittedTotal` as `money`
- `claim_external_reference` -> `claim.externalReference` as `string`
- `claim_notes` -> `source_record.notes` as `string`

Known extension work to check in GCS-SSC: the current
`gcs-gcforms-integration` sync path imports mapped values into
`extensions.gcs_gcforms_submissions`, but it does not create rows in
`extensions.gcs_gcforms_destination_links`. The claim entity tab reads from that
link table, so the stream-level sync can work while the Claim tab still appears
empty until the extension links imported submissions to the current claim owner.

## Other Seeded API Forms

- `clg17xha50008efkgfgxa8l4f`, credential `local-smoke-gcforms`
- `clocalapi0000000000000000`, credential `local-second-gcforms`

Print a different credential:

```bash
docker compose exec -T \
  -e GC_FORMS_CREDENTIAL_ID=local-smoke-gcforms \
  omnibus \
  node /opt/gcforms/scripts/print-local-credential.mjs
```

## Lifecycle

Stop and start the same seeded instance:

```bash
docker compose stop
docker compose start
```

Remove containers while keeping the persistent data volume:

```bash
docker compose down
```

Remove all local data and generated keys:

```bash
docker compose down
docker ps -aq --filter name=gcforms-omnibus-lambda | xargs -r docker rm -f
docker volume rm gcforms-omnibus-data
```

## Hosted GCForms Switch

The local API client contract is intentionally the hosted GCForms contract. To
switch GCS-SSC later, replace only the GCForms URLs and credential JSON:

- API base URL: `https://api.forms-formulaires.alpha.canada.ca/v1`
- Identity provider URL: `https://auth.forms-formulaires.alpha.canada.ca`
- `GCS_GCFORMS_CREDENTIALS_JSON`: hosted GCForms private API key JSON

## Upstream Projects

This local test bundle is based on modified copies of upstream GCForms
repositories from `cds-snc`, including:

- `platform-forms-client`
- `forms-api`
- `forms-terraform`

Original upstream license files remain in the corresponding subdirectories.

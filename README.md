# GCForms Local Test

`gcforms-localtest` packages GCForms, the Forms API, a local GCForms-style
identity provider, LocalStack, Postgres, Redis, seeded users, seeded forms, and
sample submissions into one Docker Compose workflow for local integration tests.

## Quick Access

Seeded admin login:

- Email: `local.admin@cds-snc.ca`
- Password: any non-empty password, for example `password123`
- MFA code: `12345`

Other active seeded users:

- `local.manager@cds-snc.ca`
- `local.builder@cds-snc.ca`
- `local.viewer@cds-snc.ca`

The seeded claims form is published as form ID
`clocalclaims0000000000000`.

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

## Public Test Deployment

This bundle can be exposed on a public test host, but it is still not production
software. Put it behind whatever access control is appropriate for your test
environment and do not collect real submissions.

The app, API, and IDP need public URLs. Use either three hostnames behind a
reverse proxy, or one host with three public ports:

```bash
GC_FORMS_PUBLIC_APP_URL=https://forms-test.example.com \
GC_FORMS_PUBLIC_API_URL=https://forms-api-test.example.com \
GC_FORMS_PUBLIC_IDP_URL=https://forms-idp-test.example.com \
docker compose up -d --build --wait
```

For a simple port-based test host:

```bash
GC_FORMS_PUBLIC_APP_URL=https://example.com:3000 \
GC_FORMS_PUBLIC_API_URL=https://example.com:3001 \
GC_FORMS_PUBLIC_IDP_URL=https://example.com:8080 \
docker compose up -d --build --wait
```

Sub-path hosting, such as `https://example.com/forms`, is not supported by this
local bundle. Use separate hostnames or ports that forward to:

- app -> container port `3000`
- API -> container port `3001`
- IDP -> container port `8080`

The backing service ports are bound to `127.0.0.1` by default for public-host
safety:

- LocalStack -> `4566`
- Postgres -> `4510`
- Redis -> `6379`

See [.env.public.example](.env.public.example) for the full set of public URL,
bind IP, and host port variables.

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

### API Credential Source

Hosted GCForms normally lets a form owner create and view/download a private API
key through the form settings UI. This local bundle instead seeds the claims API
credential during bootstrap so integration tests can run immediately.

The seeded credential behaves like a hosted GCForms API key when calling the
Forms API, but the local UI is not the source of truth for retrieving it. Use the
helper command below to print the exact credential JSON for this deployment.

Print the exact `GCS_GCFORMS_CREDENTIALS_JSON` value for GCS-SSC:

```bash
docker compose exec -T omnibus \
  node /opt/gcforms/scripts/print-local-credential.mjs
```

That command outputs JSON keyed by `local-claims-gcforms`. Use the whole output
as the GCS-SSC environment variable value. The credential `userId` is the local
service account id, matching the shape of a hosted GCForms private API key.

The generated private key is tied to the current Docker volume. If you remove
the `gcforms-omnibus-data` volume and reseed the stack, print the credential
again because the key may change.

The seeded claims submissions contain these GCForms question IDs:

- `agreement_number`: `AGR-0051`
- `fiscal_year`: `2025-2026`
- `claim_period_start_month`: `April`
- `claim_period_end_month`: `June`
- `submitted_line_items`: repeating rows with `submitted_item` and `submitted_amount`
- `claim_notes`: local test note

The form intentionally does not ask for agreement title, claim name, or external
reference. Agreement lookup should come from `agreement_number`.

The seeded fiscal year dropdown is limited to the two fiscal years seeded for
the agency that owns GCS agreement 51: `2025-2026` and `2026-2027`.

The seeded claim item dropdown is limited to agreement 51 budget rows:

- `Operating Costs -> Administration -> Equipment`
- `Operating Costs -> Delivery -> Travel`

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

For public test deployment, use your public API and IDP URLs instead, for
example `https://forms-api-test.example.com/v1` and
`https://forms-idp-test.example.com`.

Suggested initial mappings:

- `agreement_number` -> `agreement.number` as `string`
- `fiscal_year` -> `claim.fiscalYear` as `string`
- `claim_period_start_month` -> `claim.periodStart` using an April-to-March month transform
- `claim_period_end_month` -> `claim.periodEnd` using an April-to-March month transform
- `submitted_line_items` -> `claim_line_item[]` as `json`, then expand rows by `submitted_item`
- `claim_notes` -> `source_record.notes` as `string`

Known extension work to check in GCS-SSC: the current
`gcs-gcforms-integration` sync path imports mapped values into
`extensions.gcs_gcforms_submissions`, but it does not create rows in
`extensions.gcs_gcforms_destination_links`. The claim entity tab reads from that
link table, so the stream-level sync can work while the Claim tab still appears
empty until the extension links imported submissions to the current claim owner.

The extension also needs a small transform layer before this repeated claims
form can hydrate native GCS claim fields end to end: translate month labels to
GCS numeric months (`April = 0`, `March = 11`) and expand the
`submitted_line_items` dynamic row into claim line item records by matching
`submitted_item` against the concatenated budget label.

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

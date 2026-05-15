# GCForms Local Test

`gcforms-localtest` packages the Government of Canada GCForms application,
Forms API, local AWS-compatible services, and seed data into a local Docker
Compose workflow for integration testing.

## Not For Production

This repository is only for local development, testing, modelling, and API
integration experiments.

Do not use it for production or real submissions. It intentionally uses local
authentication bypasses, fixed test MFA codes, local bearer tokens, LocalStack
instead of AWS, generated local RSA keys, permissive local database settings,
and seeded test users.

## What It Runs

The default Compose stack starts one omnibus container that supervises:

- GCForms web application
- Forms API
- Postgres
- Redis
- LocalStack
- Submission Lambda
- Reliability Lambda
- Seeded users, forms, API service accounts, and sample submissions

LocalStack starts Lambda runtime helper containers through Docker. This is why
the Compose file mounts `/var/run/docker.sock`.

## Prerequisites

- Docker with Docker Compose
- Network access on first build to download base images and Node/Yarn/Pnpm
  dependencies

## One Command

From the repository root:

```bash
docker compose up -d --build --wait
```

When the command returns, the main container health check has passed.

## URLs

- GCForms web app: http://localhost:3000
- Forms API: http://localhost:3001
- LocalStack AWS APIs: http://localhost:4566
- Postgres: `127.0.0.1:4510`
- Redis: `127.0.0.1:6379`

## Seeded Login

Local login accepts any non-empty password for active seeded users. The MFA code
is always `12345`.

- `local.admin@cds-snc.ca`
- `local.manager@cds-snc.ca`
- `local.builder@cds-snc.ca`
- `local.viewer@cds-snc.ca`

`local.inactive@cds-snc.ca` is seeded but inactive.

## Seeded API Forms

Public forms:

- http://localhost:3000/en/id/clg17xha50008efkgfgxa8l4f
- http://localhost:3000/en/id/clocalapi0000000000000000

Forms API service accounts:

- Form `clg17xha50008efkgfgxa8l4f`
  - Token: `local:clg17xha50008efkgfgxa8l4f:local-service-account`
  - Private key in container: `/data/local-secrets/local-service-account-private.pem`
- Form `clocalapi0000000000000000`
  - Token: `local:clocalapi0000000000000000:local-second-service-account`
  - Private key in container: `/data/local-secrets/local-second-service-account-private.pem`

List new submissions:

```bash
curl -H 'Authorization: Bearer local:clg17xha50008efkgfgxa8l4f:local-service-account' \
  http://localhost:3001/v1/forms/clg17xha50008efkgfgxa8l4f/submission/new
```

Run the decrypting API smoke test:

```bash
docker compose exec -T omnibus node /opt/gcforms/scripts/api-local-smoke.mjs
```

Second seeded service account:

```bash
docker compose exec -T \
  -e GC_FORMS_FORM_ID=clocalapi0000000000000000 \
  -e GC_FORMS_SERVICE_ACCOUNT_ID=local-second-service-account \
  omnibus \
  node /opt/gcforms/scripts/api-local-smoke.mjs
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

## Development Stack

The old dependency-only stack is preserved for development work:

```bash
docker compose -f docker-compose.dev.yml up -d postgres redis localstack
```

Then run the app and API directly from the checked-out source directories.

## Upstream Projects

This local test bundle is based on modified copies of upstream GCForms
repositories from `cds-snc`, including:

- `platform-forms-client`
- `forms-api`
- `forms-terraform`

Original upstream license files remain in the corresponding subdirectories.

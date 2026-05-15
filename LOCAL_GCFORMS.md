# Local GCForms

This workspace runs GCForms locally without Azure or AWS accounts. AWS services are
provided by LocalStack and the Forms API uses local bearer tokens for seeded
service accounts.

## One Command

From this directory, run:

```bash
cd /home/omar/Code/forms
docker compose up -d --build --wait
```

That builds `gcforms-omnibus:local`, starts the container, runs bootstrap, and
waits for the API health check to pass.

## Omnibus Image

The Docker socket mount is required because LocalStack starts Lambda runtime
containers for the Submission and Reliability functions. Those helper containers
are named `gcforms-omnibus-lambda-*`. The app, API, database, Redis, LocalStack,
seed data, and Lambda deployment all live in the omnibus image.

When `docker compose up -d --build --wait` completes, these endpoints are ready:

- GCForms web app: http://localhost:3000
- Forms API: http://localhost:3001
- LocalStack AWS APIs: http://localhost:4566
- Postgres: `127.0.0.1:4510`
- Redis: `127.0.0.1:6379`

Stop and start the same seeded instance:

```bash
docker compose stop
docker compose start
```

Remove the persisted data and start clean:

```bash
docker compose down
docker ps -aq --filter name=gcforms-omnibus-lambda | xargs -r docker rm -f
docker volume rm gcforms-omnibus-data
```

## Seeded Users

Local login accepts any non-empty password for active seeded users. The MFA code
is `12345`.

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
  - Private key in omnibus: `/data/local-secrets/local-service-account-private.pem`
- Form `clocalapi0000000000000000`
  - Token: `local:clocalapi0000000000000000:local-second-service-account`
  - Private key in omnibus: `/data/local-secrets/local-second-service-account-private.pem`

List new submissions from the host:

```bash
curl -H 'Authorization: Bearer local:clg17xha50008efkgfgxa8l4f:local-service-account' \
  http://localhost:3001/v1/forms/clg17xha50008efkgfgxa8l4f/submission/new
```

Run the decrypting API smoke test inside the omnibus container:

```bash
docker compose exec -T omnibus node /opt/gcforms/scripts/api-local-smoke.mjs
```

Second service account:

```bash
docker compose exec -T \
  -e GC_FORMS_FORM_ID=clocalapi0000000000000000 \
  -e GC_FORMS_SERVICE_ACCOUNT_ID=local-second-service-account \
  omnibus \
  node /opt/gcforms/scripts/api-local-smoke.mjs
```

## Development Stack

The non-omnibus development stack is still available:

```bash
cd /home/omar/Code/forms
docker compose -f docker-compose.dev.yml up -d postgres redis localstack
./scripts/setup-local-aws.sh
./scripts/seed-local-data.sh
./scripts/deploy-local-lambdas.sh
./scripts/seed-local-submissions.sh
```

Client:

```bash
cd /home/omar/Code/forms/platform-forms-client
PATH=/home/omar/Code/forms/.tools/node-v24.15.0-linux-x64/bin:$PATH \
  node .yarn/releases/yarn-4.14.0.cjs dev
```

API:

```bash
cd /home/omar/Code/forms/forms-api
PATH=/home/omar/Code/forms/.tools/node-v24.15.0-linux-x64/bin:$PATH \
  corepack pnpm dev
```

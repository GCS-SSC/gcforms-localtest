# Local GCForms

Run the full local GCForms stack from this repository:

```bash
docker compose up -d --build --wait
```

Ready endpoints:

- GCForms web app: http://localhost:3000
- Forms API: http://localhost:3001/v1
- Local GCForms IDP: http://localhost:8080
- LocalStack AWS APIs: http://localhost:4566
- Postgres: `127.0.0.1:4510`
- Redis: `127.0.0.1:6379`

Local login users are `local.admin@cds-snc.ca`, `local.manager@cds-snc.ca`,
`local.builder@cds-snc.ca`, and `local.viewer@cds-snc.ca`. Use any non-empty
password and MFA code `12345`.

## Claims Integration Seed

- Public form: http://localhost:3000/en/id/clocalclaims0000000000000
- Form ID: `clocalclaims0000000000000`
- Credential ID: `local-claims-gcforms`
- API base URL: `http://localhost:3001/v1`
- IDP URL: `http://localhost:8080`
- Project identifier: `284778202772022819`

Print the GCS-SSC credential JSON:

```bash
docker compose exec -T omnibus \
  node /opt/gcforms/scripts/print-local-credential.mjs
```

Smoke test the real-style API flow:

```bash
docker compose exec -T \
  -e GC_FORMS_FORM_ID=clocalclaims0000000000000 \
  -e GC_FORMS_SERVICE_ACCOUNT_ID=local-claims-service-account \
  omnibus \
  node /opt/gcforms/scripts/api-local-smoke.mjs
```

The API flow is private-key JWT to `/oauth/v2/token`, then opaque bearer token
to the Forms API. This matches the hosted GCForms client contract.

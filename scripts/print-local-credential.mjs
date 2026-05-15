#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";

const credentialId = process.env.GC_FORMS_CREDENTIAL_ID ?? "local-claims-gcforms";
const credentialsPath =
  process.env.GC_FORMS_CREDENTIALS_PATH ?? "/data/local-secrets/gcforms-api-credentials.json";
const wrapForGcs = process.env.GC_FORMS_WRAP_FOR_GCS !== "false";

if (!existsSync(credentialsPath)) {
  throw new Error(`Credential file does not exist: ${credentialsPath}`);
}

const credentials = JSON.parse(readFileSync(credentialsPath, "utf8"));
const credential = credentials[credentialId];
if (!credential) {
  throw new Error(`Credential ${credentialId} does not exist in ${credentialsPath}`);
}

console.log(JSON.stringify(wrapForGcs ? { [credentialId]: credential } : credential, null, 2));

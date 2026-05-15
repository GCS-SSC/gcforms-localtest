#!/usr/bin/env node
import { createDecipheriv, createPrivateKey, createSign, privateDecrypt } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const formId = process.env.GC_FORMS_FORM_ID ?? "clg17xha50008efkgfgxa8l4f";
const serviceAccountId = process.env.GC_FORMS_SERVICE_ACCOUNT_ID ?? "local-service-account";
const keyId = process.env.GC_FORMS_KEY_ID ?? `${serviceAccountId}-public-key`;
const userId = process.env.GC_FORMS_USER_ID ?? formId;
const apiUrl = process.env.GC_FORMS_API_URL ?? "http://localhost:3001";
const identityProviderUrl =
  process.env.GC_FORMS_IDENTITY_PROVIDER_URL ?? "http://localhost:8080";
const projectIdentifier =
  process.env.GC_FORMS_PROJECT_IDENTIFIER ?? "284778202772022819";
const hostPrivateKeyPath = path.join(rootDir, "local-secrets", `${serviceAccountId}-private.pem`);
const omnibusPrivateKeyPath = `/data/local-secrets/${serviceAccountId}-private.pem`;
const privateKeyPath =
  process.env.GC_FORMS_PRIVATE_KEY ??
  (existsSync(omnibusPrivateKeyPath) ? omnibusPrivateKeyPath : hostPrivateKeyPath);

const base64Url = (value) => Buffer.from(value).toString("base64url");

function signJwt() {
  const now = Math.floor(Date.now() / 1000);
  const privateKey = readFileSync(privateKeyPath, "utf8");
  createPrivateKey({ key: privateKey });

  const header = {
    alg: "RS256",
    kid: keyId,
  };
  const payload = {
    iat: now,
    exp: now + 60,
    iss: userId,
    sub: userId,
    aud: identityProviderUrl,
  };
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = createSign("RSA-SHA256")
    .update(signingInput)
    .end()
    .sign(privateKey);

  return `${signingInput}.${base64Url(signature)}`;
}

async function generateAccessToken() {
  if (process.env.GC_FORMS_TOKEN) {
    return process.env.GC_FORMS_TOKEN;
  }

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: signJwt(),
    scope: `openid profile urn:zitadel:iam:org:project:id:${projectIdentifier}:aud`,
  });

  const response = await fetch(`${identityProviderUrl}/oauth/v2/token`, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
    },
    body,
  });

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
  }

  const payload = await response.json();
  if (typeof payload.access_token !== "string") {
    throw new Error("Token response did not include access_token");
  }
  return payload.access_token;
}

async function apiGet(route, token) {
  const response = await fetch(`${apiUrl}${route}`, {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
  }

  return response.json();
}

function decryptSubmission(encryptedPayload) {
  const privateKey = readFileSync(privateKeyPath, "utf8");
  const decrypt = (value) =>
    privateDecrypt(
      {
        key: privateKey,
        oaepHash: "sha256",
      },
      Buffer.from(value, "base64"),
    );

  const encryptionKey = decrypt(encryptedPayload.encryptedKey);
  const nonce = decrypt(encryptedPayload.encryptedNonce);
  const authTag = decrypt(encryptedPayload.encryptedAuthTag);

  const decipher = createDecipheriv("aes-256-gcm", encryptionKey, nonce);
  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedPayload.encryptedResponses, "base64")),
    decipher.final(),
  ]).toString("utf8");

  return JSON.parse(decrypted);
}

const token = await generateAccessToken();
const submissions = await apiGet(`/v1/forms/${formId}/submission/new`, token);

if (submissions.length === 0) {
  throw new Error(`No new submissions exist for ${formId}`);
}

const submissionName = submissions.at(-1).name;
const encryptedSubmission = await apiGet(`/v1/forms/${formId}/submission/${submissionName}`, token);
const decryptedSubmission = decryptSubmission(encryptedSubmission);

console.log(
  JSON.stringify(
    {
      apiUrl,
      identityProviderUrl,
      formId,
      serviceAccountId,
      keyId,
      userId,
      privateKeyPath,
      submissionName,
      decryptedSubmission,
    },
    null,
    2,
  ),
);

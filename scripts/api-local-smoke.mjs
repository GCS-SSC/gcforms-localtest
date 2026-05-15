#!/usr/bin/env node
import { createDecipheriv, privateDecrypt } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const formId = process.env.GC_FORMS_FORM_ID ?? "clg17xha50008efkgfgxa8l4f";
const serviceAccountId = process.env.GC_FORMS_SERVICE_ACCOUNT_ID ?? "local-service-account";
const apiUrl = process.env.GC_FORMS_API_URL ?? "http://localhost:3001";
const token = process.env.GC_FORMS_TOKEN ?? `local:${formId}:${serviceAccountId}`;
const hostPrivateKeyPath = path.join(rootDir, "local-secrets", `${serviceAccountId}-private.pem`);
const omnibusPrivateKeyPath = `/data/local-secrets/${serviceAccountId}-private.pem`;
const privateKeyPath =
  process.env.GC_FORMS_PRIVATE_KEY ??
  (existsSync(omnibusPrivateKeyPath) ? omnibusPrivateKeyPath : hostPrivateKeyPath);

async function apiGet(route) {
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

const submissions = await apiGet(`/v1/forms/${formId}/submission/new`);

if (submissions.length === 0) {
  throw new Error(`No new submissions exist for ${formId}`);
}

const submissionName = submissions.at(-1).name;
const encryptedSubmission = await apiGet(`/v1/forms/${formId}/submission/${submissionName}`);
const decryptedSubmission = decryptSubmission(encryptedSubmission);

console.log(
  JSON.stringify(
    {
      apiUrl,
      formId,
      serviceAccountId,
      token,
      privateKeyPath,
      submissionName,
      decryptedSubmission,
    },
    null,
    2,
  ),
);

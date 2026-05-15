#!/usr/bin/env node
import { createServer } from "node:http";
import { createHash, randomBytes, verify } from "node:crypto";
import { readFileSync } from "node:fs";

const host = process.env.LOCAL_IDP_HOST ?? "0.0.0.0";
const port = Number(process.env.LOCAL_IDP_PORT ?? "8080");
const registryPath =
  process.env.LOCAL_IDP_REGISTRY_PATH ?? "/data/local-secrets/local-idp-credentials.json";
const issuer = process.env.LOCAL_IDP_ISSUER ?? `http://localhost:${port}`;
const tokenTtlSeconds = Number(process.env.LOCAL_IDP_TOKEN_TTL_SECONDS ?? "1800");

const issuedTokens = new Map();

const jsonResponse = (response, statusCode, payload) => {
  response.writeHead(statusCode, {
    "content-type": "application/json",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(payload));
};

const readBody = async (request) => {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
};

const parseBody = async (request) => {
  const raw = await readBody(request);
  const contentType = request.headers["content-type"] ?? "";
  if (contentType.includes("application/json")) {
    return raw ? JSON.parse(raw) : {};
  }
  return Object.fromEntries(new URLSearchParams(raw));
};

const base64UrlJson = (value) =>
  JSON.parse(Buffer.from(value, "base64url").toString("utf8"));

const loadRegistry = () => {
  try {
    const parsed = JSON.parse(readFileSync(registryPath, "utf8"));
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
};

const registryEntries = () => Object.values(loadRegistry());

const findCredential = (keyId) =>
  registryEntries().find((entry) => entry?.keyId === keyId);

const validateAssertion = (assertion) => {
  const [encodedHeader, encodedPayload, encodedSignature] = assertion.split(".");
  if (!encodedHeader || !encodedPayload || !encodedSignature) {
    throw new Error("assertion is not a signed JWT");
  }

  const header = base64UrlJson(encodedHeader);
  const payload = base64UrlJson(encodedPayload);
  if (header.alg !== "RS256" || typeof header.kid !== "string") {
    throw new Error("assertion must use RS256 and a key id");
  }

  const credential = findCredential(header.kid);
  if (!credential) {
    throw new Error(`unknown key id ${header.kid}`);
  }

  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = Buffer.from(encodedSignature, "base64url");
  const valid = verify("RSA-SHA256", Buffer.from(signingInput), credential.publicKey, signature);
  if (!valid) {
    throw new Error("assertion signature is invalid");
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== "number" || payload.exp < now) {
    throw new Error("assertion is expired");
  }

  if (typeof payload.iat === "number" && payload.iat > now + 60) {
    throw new Error("assertion is not valid yet");
  }

  if (payload.iss !== credential.userId || payload.sub !== credential.userId) {
    throw new Error("assertion subject does not match the API credential");
  }

  return credential;
};

const tokenResponse = async (request, response) => {
  try {
    const body = await parseBody(request);
    if (body.grant_type !== "urn:ietf:params:oauth:grant-type:jwt-bearer") {
      jsonResponse(response, 400, { error: "unsupported_grant_type" });
      return;
    }

    if (typeof body.assertion !== "string" || body.assertion.length === 0) {
      jsonResponse(response, 400, { error: "invalid_request" });
      return;
    }

    const credential = validateAssertion(body.assertion);
    const accessToken = `local-idp.${randomBytes(32).toString("base64url")}`;
    const exp = Math.floor(Date.now() / 1000) + tokenTtlSeconds;
    issuedTokens.set(accessToken, {
      active: true,
      exp,
      sub: credential.serviceAccountId,
      username: credential.formId,
      client_id: credential.userId,
      iss: issuer,
    });

    jsonResponse(response, 200, {
      access_token: accessToken,
      token_type: "Bearer",
      expires_in: tokenTtlSeconds,
      scope: typeof body.scope === "string" ? body.scope : "openid profile",
    });
  } catch (error) {
    jsonResponse(response, 401, {
      error: "invalid_grant",
      error_description: error instanceof Error ? error.message : String(error),
    });
  }
};

const introspectionResponse = async (request, response) => {
  try {
    const body = await parseBody(request);
    const token = typeof body.token === "string" ? body.token : "";
    const activeToken = issuedTokens.get(token);
    if (!activeToken || activeToken.exp <= Math.floor(Date.now() / 1000)) {
      jsonResponse(response, 200, { active: false });
      return;
    }
    jsonResponse(response, 200, activeToken);
  } catch {
    jsonResponse(response, 200, { active: false });
  }
};

const server = createServer((request, response) => {
  if (request.method === "GET" && request.url === "/status") {
    jsonResponse(response, 200, {
      ok: true,
      registrySha256: createHash("sha256")
        .update(JSON.stringify(loadRegistry()))
        .digest("hex"),
    });
    return;
  }

  if (request.method === "POST" && request.url === "/oauth/v2/token") {
    void tokenResponse(request, response);
    return;
  }

  if (request.method === "POST" && request.url === "/oauth/v2/introspect") {
    void introspectionResponse(request, response);
    return;
  }

  jsonResponse(response, 404, { error: "not_found" });
});

server.listen(port, host, () => {
  console.log(`Local GCForms IDP listening on http://${host}:${port}`);
});

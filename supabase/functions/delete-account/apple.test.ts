import { assert, assertEquals } from "../_shared/testing.ts";
import { appleConfigFromEnv, clientSecret, revokeAppleTokens } from "./apple.ts";

async function testConfig() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
  return {
    config: { teamId: "TEAM123", keyId: "KEY456", clientId: "com.example.atrox", privateKeyPem: pem },
    publicKey: pair.publicKey,
  };
}

function decode(part: string): Uint8Array<ArrayBuffer> {
  const base64 = part.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (part.length % 4)) % 4);
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

Deno.test("the client secret is an ES256 JWT Apple can verify", async () => {
  const { config, publicKey } = await testConfig();
  const jwt = await clientSecret(config, new Date("2026-11-13T10:00:00Z"));
  const [header, payload, signature] = jwt.split(".");

  assertEquals(JSON.parse(new TextDecoder().decode(decode(header))), { alg: "ES256", kid: "KEY456" });
  const claims = JSON.parse(new TextDecoder().decode(decode(payload)));
  assertEquals(claims, {
    iss: "TEAM123",
    iat: 1794564000,
    exp: 1794564300,
    aud: "https://appleid.apple.com",
    sub: "com.example.atrox",
  });
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    decode(signature),
    new TextEncoder().encode(`${header}.${payload}`),
  );
  assert(valid, "signature does not verify");
});

Deno.test("revocation exchanges the code, then revokes the refresh token", async () => {
  const { config } = await testConfig();
  const calls: { url: string; body: URLSearchParams }[] = [];
  const fetcher = (url: string, init?: RequestInit) => {
    calls.push({ url, body: new URLSearchParams(String(init?.body)) });
    const body = url.endsWith("/auth/token") ? { refresh_token: "r-1", access_token: "a-1" } : {};
    return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
  };

  await revokeAppleTokens("code-1", config, fetcher);

  assertEquals(calls.map((call) => call.url), [
    "https://appleid.apple.com/auth/token",
    "https://appleid.apple.com/auth/revoke",
  ]);
  assertEquals(calls[0].body.get("code"), "code-1");
  assertEquals(calls[0].body.get("grant_type"), "authorization_code");
  assertEquals(calls[1].body.get("token"), "r-1");
  assertEquals(calls[1].body.get("token_type_hint"), "refresh_token");
  assertEquals(calls[1].body.get("client_id"), "com.example.atrox");
});

Deno.test("an Apple error is thrown", async () => {
  const { config } = await testConfig();
  let failed = false;
  try {
    await revokeAppleTokens("code-1", config, () => Promise.resolve(new Response("{}", { status: 400 })));
  } catch {
    failed = true;
  }
  assert(failed, "expected an error");
});

Deno.test("Apple config comes from the secrets and is optional", () => {
  assertEquals(appleConfigFromEnv(() => undefined), null);
  const env: Record<string, string> = {
    APPLE_TEAM_ID: "T",
    APPLE_KEY_ID: "K",
    APPLE_CLIENT_ID: "C",
    APPLE_PRIVATE_KEY: "a\\nb",
  };
  assertEquals(appleConfigFromEnv((name) => env[name])?.privateKeyPem, "a\nb");
});

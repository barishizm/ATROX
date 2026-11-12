// Sign in with Apple token revocation (App Store Review Guideline 5.1.1(v)): the app sends a fresh authorization
// code, we exchange it for a refresh token and revoke that.
// https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

export interface AppleConfig {
  teamId: string;
  keyId: string;
  /** The Services ID / bundle id the code was issued to. */
  clientId: string;
  /** The .p8 key, PEM (PKCS#8). */
  privateKeyPem: string;
}

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

const APPLE = "https://appleid.apple.com";

function base64url(bytes: Uint8Array): string {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
}

/** The ES256 JWT Apple wants as `client_secret` (valid for 5 minutes). */
export async function clientSecret(config: AppleConfig, now: Date = new Date()): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const iat = Math.floor(now.getTime() / 1000);
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const payload = base64url(encoder.encode(JSON.stringify({
    iss: config.teamId,
    iat,
    exp: iat + 300,
    aud: APPLE,
    sub: config.clientId,
  })));
  // WebCrypto returns the raw r‖s signature, which is exactly the JWS ES256 format.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

/** Exchanges `code` and revokes the resulting token. Throws on any Apple error. */
export async function revokeAppleTokens(
  code: string,
  config: AppleConfig,
  fetcher: Fetch = fetch,
  now?: Date,
): Promise<void> {
  const secret = await clientSecret(config, now);
  const form = (fields: Record<string, string>) => ({
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  const tokenResponse = await fetcher(
    `${APPLE}/auth/token`,
    form({
      client_id: config.clientId,
      client_secret: secret,
      code,
      grant_type: "authorization_code",
    }),
  );
  if (!tokenResponse.ok) throw new Error(`apple token exchange: HTTP ${tokenResponse.status}`);
  const tokens = await tokenResponse.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) throw new Error("apple token exchange: no token");
  const revokeResponse = await fetcher(
    `${APPLE}/auth/revoke`,
    form({
      client_id: config.clientId,
      client_secret: secret,
      token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  );
  if (!revokeResponse.ok) throw new Error(`apple revoke: HTTP ${revokeResponse.status}`);
}

/** Apple settings from the function secrets; null when they are not configured. */
export function appleConfigFromEnv(env: (name: string) => string | undefined): AppleConfig | null {
  const teamId = env("APPLE_TEAM_ID");
  const keyId = env("APPLE_KEY_ID");
  const clientId = env("APPLE_CLIENT_ID");
  const privateKeyPem = env("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !privateKeyPem) return null;
  return { teamId, keyId, clientId, privateKeyPem: privateKeyPem.replace(/\\n/g, "\n") };
}

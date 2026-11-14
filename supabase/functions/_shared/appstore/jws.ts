// Verification of App Store signed data (P090): notifications V2 `signedPayload`, `signedTransactionInfo`,
// `signedRenewalInfo` and StoreKit 2's `jwsRepresentation`. Follows Apple's App Store Server Library checks:
//   - header alg ES256 with an x5c chain of exactly three certificates: leaf, intermediate, root;
//   - the root is byte-for-byte a pinned Apple root (Apple Root CA - G3);
//   - each certificate is signed by the next and valid at the effective date (the payload's signedDate when present —
//     Apple's offline mode — otherwise now); the intermediate is a CA;
//   - the leaf carries Apple's Mac App Store receipt-signing OID, the intermediate the WWDR OID;
//   - the JWS signature verifies with the leaf key.
// Revocation (OCSP) is not checked; see docs/ILERLEME.md "Ertelenenler".
import { APPLE_ROOT_CA_G3_BASE64 } from "./apple-root.ts";
import { base64ToBytes, base64UrlToBytes, bytesEqual } from "./der.ts";
import { type Certificate, importPublicKey, isSignedBy, parseCertificate } from "./x509.ts";

export const OID_APPLE_LEAF = "1.2.840.113635.100.6.11.1";
export const OID_APPLE_WWDR_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

export class JwsError extends Error {
  constructor(public reason: string) {
    super(reason);
  }
}

export interface JwsVerifierOptions {
  /** DER roots to trust; defaults to Apple Root CA - G3. Tests pass their own. */
  roots?: Uint8Array[];
  now?: () => number;
}

export type JwsVerifier = <T = Record<string, unknown>>(jws: string) => Promise<T>;

export function createJwsVerifier(options: JwsVerifierOptions = {}): JwsVerifier {
  const roots = options.roots ?? [base64ToBytes(APPLE_ROOT_CA_G3_BASE64)];
  const now = options.now ?? Date.now;
  return async <T>(jws: string): Promise<T> => {
    const parts = typeof jws === "string" ? jws.split(".") : [];
    if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) throw new JwsError("malformed");
    const [headerPart, payloadPart, signaturePart] = parts;

    let header: { alg?: unknown; x5c?: unknown };
    let payload: Record<string, unknown>;
    try {
      header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(headerPart)));
      payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(payloadPart)));
    } catch {
      throw new JwsError("malformed");
    }
    if (header.alg !== "ES256") throw new JwsError("unsupported_alg");
    if (!Array.isArray(header.x5c) || header.x5c.length !== 3 || header.x5c.some((c) => typeof c !== "string")) {
      throw new JwsError("bad_chain");
    }

    let chain: Certificate[];
    try {
      chain = (header.x5c as string[]).map((c) => parseCertificate(base64ToBytes(c)));
    } catch {
      throw new JwsError("bad_chain");
    }
    const [leaf, intermediate, root] = chain;
    if (!roots.some((trusted) => bytesEqual(trusted, root.der))) throw new JwsError("untrusted_root");
    if (!leaf.extensions.has(OID_APPLE_LEAF)) throw new JwsError("bad_leaf");
    if (!intermediate.extensions.has(OID_APPLE_WWDR_INTERMEDIATE) || !intermediate.isCA) {
      throw new JwsError("bad_intermediate");
    }

    const signedDate = typeof payload.signedDate === "number" ? payload.signedDate : undefined;
    const effective = signedDate ?? now();
    if (chain.some((c) => effective < c.notBefore || effective > c.notAfter)) throw new JwsError("expired_chain");
    if (!(await isSignedBy(leaf, intermediate)) || !(await isSignedBy(intermediate, root))) {
      throw new JwsError("bad_chain_signature");
    }

    let valid = false;
    try {
      const key = await importPublicKey(leaf);
      const signature = base64UrlToBytes(signaturePart);
      const input = new TextEncoder().encode(`${headerPart}.${payloadPart}`);
      valid = signature.length === 64 &&
        await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature as BufferSource, input as BufferSource);
    } catch {
      valid = false;
    }
    if (!valid) throw new JwsError("bad_signature");
    return payload as T;
  };
}

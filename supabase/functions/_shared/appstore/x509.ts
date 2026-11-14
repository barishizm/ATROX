// X.509 subset for Apple's signed data (P090): EC keys (P-256 / P-384), ecdsa-with-SHA256/384 signatures.
import { bytesEqual, children, decodeOid, decodeTime, type DerNode, DerError, ecdsaDerToRaw, readNode } from "./der.ts";

const OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, { name: "P-256" | "P-384"; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const SIGNATURE_HASH: Record<string, "SHA-256" | "SHA-384"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};
const OID_BASIC_CONSTRAINTS = "2.5.29.19";

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: number;
  notAfter: number;
  spki: Uint8Array;
  curve: string;
  extensions: Set<string>;
  isCA: boolean;
}

function expect(node: DerNode | undefined, tag: number, what: string): DerNode {
  if (!node || node.tag !== tag) throw new DerError(`${what}: unexpected structure`);
  return node;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const root = expect(readNode(der), 0x30, "certificate");
  if (root.bytes.length !== der.length) throw new DerError("trailing bytes after certificate");
  const [tbsNode, algNode, sigNode] = children(root);
  expect(tbsNode, 0x30, "tbsCertificate");
  const signatureAlgorithm = decodeOid(expect(children(expect(algNode, 0x30, "signatureAlgorithm"))[0], 0x06, "algorithm").content);
  const bitString = expect(sigNode, 0x03, "signatureValue").content;
  if (bitString[0] !== 0) throw new DerError("signature has unused bits");

  const fields = children(tbsNode);
  let index = fields[0]?.tag === 0xa0 ? 1 : 0; // optional [0] version
  index += 2; // serialNumber, signature
  const issuer = expect(fields[index++], 0x30, "issuer").bytes;
  const [notBefore, notAfter] = children(expect(fields[index++], 0x30, "validity"));
  const subject = expect(fields[index++], 0x30, "subject").bytes;
  const spkiNode = expect(fields[index++], 0x30, "subjectPublicKeyInfo");
  const [keyAlg] = children(spkiNode);
  const [keyOid, curveOid] = children(expect(keyAlg, 0x30, "key algorithm"));
  if (decodeOid(expect(keyOid, 0x06, "key oid").content) !== OID_EC_PUBLIC_KEY) throw new DerError("not an EC key");
  const curve = decodeOid(expect(curveOid, 0x06, "curve").content);

  const extensions = new Set<string>();
  let isCA = false;
  for (const field of fields.slice(index)) {
    if (field.tag !== 0xa3) continue;
    for (const extension of children(expect(children(field)[0], 0x30, "extensions"))) {
      const parts = children(extension);
      const oid = decodeOid(expect(parts[0], 0x06, "extension id").content);
      extensions.add(oid);
      if (oid === OID_BASIC_CONSTRAINTS) {
        const value = expect(parts[parts.length - 1], 0x04, "extension value");
        const constraints = children(expect(readNode(value.content), 0x30, "basicConstraints"));
        isCA = constraints[0]?.tag === 0x01 && constraints[0].content[0] !== 0;
      }
    }
  }

  return {
    der, tbs: tbsNode.bytes, signatureAlgorithm, signature: bitString.subarray(1), issuer, subject,
    notBefore: decodeTime(notBefore), notAfter: decodeTime(notAfter), spki: spkiNode.bytes, curve, extensions, isCA,
  };
}

export function curveOf(certificate: Certificate) {
  const curve = CURVES[certificate.curve];
  if (!curve) throw new DerError(`unsupported curve ${certificate.curve}`);
  return curve;
}

export function importPublicKey(certificate: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", certificate.spki as BufferSource, { name: "ECDSA", namedCurve: curveOf(certificate).name }, false, [
    "verify",
  ]);
}

/** Whether `child` names `issuer` as its issuer and carries a valid signature by it. */
export async function isSignedBy(child: Certificate, issuer: Certificate): Promise<boolean> {
  if (!bytesEqual(child.issuer, issuer.subject)) return false;
  const hash = SIGNATURE_HASH[child.signatureAlgorithm];
  if (!hash) return false;
  try {
    const raw = ecdsaDerToRaw(child.signature, curveOf(issuer).size);
    const key = await importPublicKey(issuer);
    return await crypto.subtle.verify({ name: "ECDSA", hash }, key, raw as BufferSource, child.tbs as BufferSource);
  } catch {
    return false;
  }
}

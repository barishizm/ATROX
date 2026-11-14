// Test-only: a fake "Apple" certificate chain shaped like the real one (P-384 root and WWDR intermediate with the
// Apple OIDs, P-256 leaf) and a signer that produces App Store style JWS (ES256 + x5c). No remote imports.
import { bytesToBase64, bytesToBase64Url } from "./der.ts";
import { OID_APPLE_LEAF, OID_APPLE_WWDR_INTERMEDIATE } from "./jws.ts";

function length(n: number): number[] {
  if (n < 0x80) return [n];
  const bytes: number[] = [];
  while (n > 0) {
    bytes.unshift(n & 0xff);
    n = Math.floor(n / 256);
  }
  return [0x80 | bytes.length, ...bytes];
}

function tlv(tag: number, ...content: Uint8Array[]): Uint8Array {
  const size = content.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array([tag, ...length(size), ...new Uint8Array(size)]);
  let offset = out.length - size;
  for (const part of content) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

const seq = (...content: Uint8Array[]) => tlv(0x30, ...content);
const set = (...content: Uint8Array[]) => tlv(0x31, ...content);

function oid(text: string): Uint8Array {
  const parts = text.split(".").map(Number);
  const bytes = [parts[0] * 40 + parts[1]];
  for (const part of parts.slice(2)) {
    const chunk = [part & 0x7f];
    let rest = Math.floor(part / 128);
    while (rest > 0) {
      chunk.unshift(0x80 | (rest & 0x7f));
      rest = Math.floor(rest / 128);
    }
    bytes.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(bytes));
}

const integer = (n: number) => tlv(0x02, new Uint8Array([n]));
const utf8 = (text: string) => tlv(0x0c, new TextEncoder().encode(text));
const octets = (bytes: Uint8Array) => tlv(0x04, bytes);
const bitString = (bytes: Uint8Array) => tlv(0x03, new Uint8Array([0]), bytes);

function time(ms: number): Uint8Array {
  const iso = new Date(ms).toISOString(); // YYYY-MM-DDTHH:MM:SS.sssZ
  const text = iso.slice(2, 4) + iso.slice(5, 7) + iso.slice(8, 10) + iso.slice(11, 13) + iso.slice(14, 16) + iso.slice(17, 19) + "Z";
  return tlv(0x17, new TextEncoder().encode(text));
}

const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), utf8(cn))));

function rawToDer(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  const int = (bytes: Uint8Array) => {
    let value = bytes;
    while (value.length > 1 && value[0] === 0 && (value[1] & 0x80) === 0) value = value.subarray(1);
    if (value[0] & 0x80) value = new Uint8Array([0, ...value]);
    return tlv(0x02, value);
  };
  return seq(int(raw.subarray(0, half)), int(raw.subarray(half)));
}

type Curve = "P-256" | "P-384";

interface Issued {
  der: Uint8Array;
  keys: CryptoKeyPair;
  subject: string;
  curve: Curve;
}

async function generate(curve: Curve): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"]) as CryptoKeyPair;
}

interface CertOptions {
  subject: string;
  curve: Curve;
  issuer?: Issued;
  ca?: boolean;
  extraOids?: string[];
  notBefore: number;
  notAfter: number;
}

async function issue(options: CertOptions): Promise<Issued> {
  const keys = await generate(options.curve);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", keys.publicKey));
  const signer = options.issuer ?? { keys, subject: options.subject, curve: options.curve, der: new Uint8Array() };
  const extensions: Uint8Array[] = [
    seq(oid("2.5.29.19"), tlv(0x01, new Uint8Array([0xff])), octets(options.ca ? seq(tlv(0x01, new Uint8Array([0xff]))) : seq())),
    ...(options.extraOids ?? []).map((id) => seq(oid(id), octets(tlv(0x05, new Uint8Array())))),
  ];
  const algorithm = seq(oid("1.2.840.10045.4.3.3")); // ecdsa-with-SHA384 (Apple signs its chain with SHA-384)
  const tbs = seq(
    tlv(0xa0, integer(2)),
    integer(1),
    algorithm,
    name(signer.subject),
    seq(time(options.notBefore), time(options.notAfter)),
    name(options.subject),
    spki,
    tlv(0xa3, seq(...extensions)),
  );
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-384" }, signer.keys.privateKey, tbs as BufferSource));
  return { der: seq(tbs, algorithm, bitString(rawToDer(raw))), keys, subject: options.subject, curve: options.curve };
}

export interface FakeAppleChain {
  root: Uint8Array;
  /** Signs a payload as App Store signed data. */
  sign(payload: unknown): Promise<string>;
}

export interface FakeChainOptions {
  leafOid?: boolean;
  intermediateOid?: boolean;
  notBefore?: number;
  notAfter?: number;
}

export async function fakeAppleChain(options: FakeChainOptions = {}): Promise<FakeAppleChain> {
  const notBefore = options.notBefore ?? Date.UTC(2020, 0, 1);
  const notAfter = options.notAfter ?? Date.UTC(2040, 0, 1);
  const root = await issue({ subject: "Fake Apple Root CA - G3", curve: "P-384", ca: true, notBefore, notAfter });
  const intermediate = await issue({
    subject: "Fake Apple WWDR CA G6", curve: "P-384", issuer: root, ca: true, notBefore, notAfter,
    extraOids: options.intermediateOid === false ? [] : [OID_APPLE_WWDR_INTERMEDIATE],
  });
  const leaf = await issue({
    subject: "Fake Mac App Store Receipt Signing", curve: "P-256", issuer: intermediate, notBefore, notAfter,
    extraOids: options.leafOid === false ? [] : [OID_APPLE_LEAF],
  });
  return {
    root: root.der,
    async sign(payload) {
      const header = { alg: "ES256", x5c: [leaf.der, intermediate.der, root.der].map(bytesToBase64) };
      const encode = (value: unknown) => bytesToBase64Url(new TextEncoder().encode(JSON.stringify(value)));
      const input = `${encode(header)}.${encode(payload)}`;
      const signature = new Uint8Array(
        await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, leaf.keys.privateKey, new TextEncoder().encode(input)),
      );
      return `${input}.${bytesToBase64Url(signature)}`;
    },
  };
}

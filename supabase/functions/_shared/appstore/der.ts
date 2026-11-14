// Minimal DER reader (P090): enough of ASN.1 to read X.509 certificates and ECDSA signatures. No remote imports.

export interface DerNode {
  tag: number;
  /** The whole TLV (tag + length + content). */
  bytes: Uint8Array;
  content: Uint8Array;
}

export class DerError extends Error {}

/** Reads one TLV starting at `offset`. */
export function readNode(data: Uint8Array, offset = 0): DerNode {
  if (offset + 2 > data.length) throw new DerError("truncated header");
  const tag = data[offset];
  if ((tag & 0x1f) === 0x1f) throw new DerError("multi-byte tags are not supported");
  let length = data[offset + 1];
  let header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new DerError("unsupported length");
    if (offset + 2 + count > data.length) throw new DerError("truncated length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + data[offset + 2 + i];
    header += count;
  }
  const end = offset + header + length;
  if (end > data.length) throw new DerError("truncated content");
  return { tag, bytes: data.subarray(offset, end), content: data.subarray(offset + header, end) };
}

/** The children of a constructed node, in order. */
export function children(node: DerNode): DerNode[] {
  if ((node.tag & 0x20) === 0) throw new DerError("not a constructed node");
  const result: DerNode[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const child = readNode(node.content, offset);
    result.push(child);
    offset += child.bytes.length;
  }
  return result;
}

export function decodeOid(content: Uint8Array): string {
  if (content.length === 0) throw new DerError("empty OID");
  const parts: number[] = [];
  const first = content[0];
  parts.push(first < 80 ? Math.floor(first / 40) : 2, first < 80 ? first % 40 : first - 80);
  let value = 0;
  for (let i = 1; i < content.length; i++) {
    value = value * 128 + (content[i] & 0x7f);
    if ((content[i] & 0x80) === 0) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

/** UTCTime (0x17) or GeneralizedTime (0x18) → epoch milliseconds. */
export function decodeTime(node: DerNode): number {
  const text = new TextDecoder().decode(node.content);
  let match: RegExpExecArray | null;
  if (node.tag === 0x17 && (match = /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text))) {
    const yy = Number(match[1]);
    const year = yy >= 50 ? 1900 + yy : 2000 + yy;
    return Date.UTC(year, Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]));
  }
  if (node.tag === 0x18 && (match = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text))) {
    return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]));
  }
  throw new DerError(`unsupported time ${text}`);
}

/** ECDSA-Sig-Value (SEQUENCE { r INTEGER, s INTEGER }) → r || s, each left-padded to `size` bytes (WebCrypto form). */
export function ecdsaDerToRaw(signature: Uint8Array, size: number): Uint8Array {
  const sequence = readNode(signature);
  if (sequence.tag !== 0x30) throw new DerError("signature is not a SEQUENCE");
  const [r, s] = children(sequence);
  if (!r || !s || r.tag !== 0x02 || s.tag !== 0x02) throw new DerError("signature is not two INTEGERs");
  const out = new Uint8Array(size * 2);
  for (const [index, integer] of [r, s].entries()) {
    let value = integer.content;
    while (value.length > 1 && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new DerError("signature integer too long");
    out.set(value, index * size + size - value.length);
  }
  return out;
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export function base64ToBytes(text: string): Uint8Array {
  const binary = atob(text);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function base64UrlToBytes(text: string): Uint8Array {
  const normal = text.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(normal + "=".repeat((4 - (normal.length % 4)) % 4));
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function bytesToBase64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

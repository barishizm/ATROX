import { assert, assertEquals } from "../testing.ts";
import { APPLE_ROOT_CA_G3_BASE64 } from "./apple-root.ts";
import { base64ToBytes } from "./der.ts";
import { createJwsVerifier, JwsError } from "./jws.ts";
import { fakeAppleChain } from "./test-chain.ts";
import { parseCertificate } from "./x509.ts";

async function rejects(promise: Promise<unknown>, reason: string) {
  try {
    await promise;
  } catch (error) {
    assert(error instanceof JwsError, `expected JwsError, got ${error}`);
    assertEquals(error.reason, reason);
    return;
  }
  throw new Error(`expected rejection ${reason}`);
}

Deno.test("the pinned Apple Root CA - G3 parses as a P-384 CA valid until 2039", async () => {
  const root = parseCertificate(base64ToBytes(APPLE_ROOT_CA_G3_BASE64));
  assertEquals(root.curve, "1.3.132.0.34");
  assert(root.isCA);
  assertEquals(new Date(root.notAfter).toISOString(), "2039-04-30T18:19:06.000Z");
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", root.der as BufferSource));
  assertEquals([...digest].map((b) => b.toString(16).padStart(2, "0")).join(""),
    "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179");
});

Deno.test("a correctly chained payload verifies and returns the payload", async () => {
  const chain = await fakeAppleChain();
  const verify = createJwsVerifier({ roots: [chain.root] });
  const jws = await chain.sign({ hello: "world", signedDate: Date.UTC(2026, 10, 14) });
  assertEquals(await verify(jws), { hello: "world", signedDate: Date.UTC(2026, 10, 14) });
});

Deno.test("a chain under another root is rejected (the default trusts only Apple)", async () => {
  const chain = await fakeAppleChain();
  const jws = await chain.sign({ a: 1 });
  await rejects(createJwsVerifier()(jws), "untrusted_root");
  const other = await fakeAppleChain();
  await rejects(createJwsVerifier({ roots: [other.root] })(jws), "untrusted_root");
});

Deno.test("a tampered payload or signature is rejected", async () => {
  const chain = await fakeAppleChain();
  const verify = createJwsVerifier({ roots: [chain.root] });
  const [h, , s] = (await chain.sign({ status: "free" })).split(".");
  const [, p2] = (await chain.sign({ status: "pro" })).split(".");
  await rejects(verify(`${h}.${p2}.${s}`), "bad_signature");
  await rejects(verify(`${h}.${p2}.${s.slice(0, -4)}AAAA`), "bad_signature");
  await rejects(verify("not-a-jws"), "malformed");
});

Deno.test("a leaf or intermediate without Apple's OIDs is rejected", async () => {
  const noLeaf = await fakeAppleChain({ leafOid: false });
  await rejects(createJwsVerifier({ roots: [noLeaf.root] })(await noLeaf.sign({})), "bad_leaf");
  const noIntermediate = await fakeAppleChain({ intermediateOid: false });
  await rejects(createJwsVerifier({ roots: [noIntermediate.root] })(await noIntermediate.sign({})), "bad_intermediate");
});

Deno.test("the chain must be valid at signedDate (or now)", async () => {
  const chain = await fakeAppleChain({ notBefore: Date.UTC(2020, 0, 1), notAfter: Date.UTC(2021, 0, 1) });
  const verify = createJwsVerifier({ roots: [chain.root], now: () => Date.UTC(2026, 0, 1) });
  await rejects(verify(await chain.sign({ signedDate: Date.UTC(2025, 0, 1) })), "expired_chain");
  await rejects(verify(await chain.sign({})), "expired_chain");
  assertEquals(await verify(await chain.sign({ signedDate: Date.UTC(2020, 5, 1) })), { signedDate: Date.UTC(2020, 5, 1) });
});

Deno.test("only ES256 with a three-certificate x5c is accepted", async () => {
  const chain = await fakeAppleChain();
  const verify = createJwsVerifier({ roots: [chain.root] });
  const [, p, s] = (await chain.sign({})).split(".");
  const enc = (v: unknown) => btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await rejects(verify(`${enc({ alg: "none" })}.${p}.${s}`), "unsupported_alg");
  await rejects(verify(`${enc({ alg: "ES256", x5c: ["AA"] })}.${p}.${s}`), "bad_chain");
});

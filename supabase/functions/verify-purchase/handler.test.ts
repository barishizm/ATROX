import { FakeAppStoreStore } from "../_shared/appstore/fake-store.ts";
import { createJwsVerifier } from "../_shared/appstore/jws.ts";
import { fakeAppleChain } from "../_shared/appstore/test-chain.ts";
import { parseEnvironments, type TransactionInfo } from "../_shared/appstore/entitlement.ts";
import { assertEquals } from "../_shared/testing.ts";
import { createVerifyPurchaseHandler } from "./handler.ts";

const NOW = Date.UTC(2026, 10, 14, 12);
const DAY = 86_400_000;
const USER = "00000000-0000-0000-0000-000000000001";
const OTHER = "00000000-0000-0000-0000-000000000002";
const TOKEN = "b74ace79-3051-5fbe-8b18-7a4c598b8ebf";
const OTHER_TOKEN = "11111111-2222-5333-8444-555555555555";
const chain = await fakeAppleChain();

const tx = (over: Partial<TransactionInfo> = {}): TransactionInfo => ({
  transactionId: "2000", originalTransactionId: "1000", productId: "atrox.pro.monthly", bundleId: "com.barishizm.atrox",
  purchaseDate: NOW - 1000, expiresDate: NOW + 30 * DAY, appAccountToken: TOKEN, environment: "Sandbox", signedDate: NOW,
  ...over,
});

function setup(environments = "Production,Sandbox") {
  const store = new FakeAppStoreStore({ [TOKEN]: USER, [OTHER_TOKEN]: OTHER });
  const handler = createVerifyPurchaseHandler({
    verify: (jwt) => Promise.resolve(({ u1: USER, u2: OTHER } as Record<string, string>)[jwt] ?? null),
    verifyJws: createJwsVerifier({ roots: [chain.root], now: () => NOW }),
    store, bundleIds: new Set(["com.barishizm.atrox"]), environments: parseEnvironments(environments), now: () => NOW,
  });
  const send = async (body: unknown, token = "u1") => {
    const response = await handler(new Request("http://x/verify-purchase", {
      method: "POST", headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body),
    }));
    return { status: response.status, body: await response.json() };
  };
  return { store, send };
}

Deno.test("a verified purchase writes the entitlement at once", async () => {
  const { store, send } = setup();
  const res = await send({ signed_transaction: await chain.sign(tx()) });
  assertEquals(res, {
    status: 200,
    body: { is_pro: true, status: "active", expires_at: new Date(NOW + 30 * DAY).toISOString(), product_id: "atrox.pro.monthly", applied: true },
  });
  assertEquals(store.rows[0].user_id, USER);
  assertEquals(store.events[0].source, "verify");
});

Deno.test("an expired or refunded transaction is recorded but grants nothing", async () => {
  const { send } = setup();
  assertEquals((await send({ signed_transaction: await chain.sign(tx({ expiresDate: NOW - 1 })) })).body.is_pro, false);
  const refunded = await send({ signed_transaction: await chain.sign(tx({ originalTransactionId: "2", revocationDate: NOW - 1 })) });
  assertEquals([refunded.body.status, refunded.body.is_pro], ["refunded", false]);
});

Deno.test("another account's token, or a transaction owned by someone else, is refused and logged", async () => {
  const { store, send } = setup();
  const mismatch = await send({ signed_transaction: await chain.sign(tx({ appAccountToken: OTHER_TOKEN })) });
  assertEquals([mismatch.status, mismatch.body.error.code, mismatch.body.error.details.reason], [409, "account_mismatch", "token_mismatch"]);
  assertEquals(store.events[0].matched, false);
  // A tokenless purchase binds to the first caller; a second account cannot take it over.
  const tokenless = await chain.sign(tx({ appAccountToken: undefined, originalTransactionId: "77" }));
  assertEquals((await send({ signed_transaction: tokenless })).status, 200);
  const takeover = await send({ signed_transaction: tokenless }, "u2");
  assertEquals([takeover.status, takeover.body.error.details.reason], [409, "owned_by_other"]);
  assertEquals(store.rows.filter((r) => r.original_transaction_id === "77").map((r) => r.user_id), [USER]);
});

Deno.test("signature, bundle, product and environment are checked", async () => {
  const { send } = setup("Sandbox");
  const stranger = await fakeAppleChain();
  const reason = async (jws: string) => (await send({ signed_transaction: jws })).body.error.details.reason;
  assertEquals(await reason(await stranger.sign(tx())), "untrusted_root");
  assertEquals(await reason(await chain.sign(tx({ bundleId: "com.other" }))), "wrong_bundle");
  assertEquals(await reason(await chain.sign(tx({ productId: "x" }))), "unknown_product");
  assertEquals(await reason(await chain.sign(tx({ environment: "Production" }))), "environment_not_accepted");
  assertEquals(await reason(await chain.sign(tx({ environment: "Xcode" }))), "unknown_environment");
});

Deno.test("auth and body shape", async () => {
  const { send } = setup();
  assertEquals((await send({ signed_transaction: "x" }, "nope")).status, 401);
  assertEquals((await send({})).status, 400);
  assertEquals((await send({ signed_transaction: "a.b.c", extra: 1 })).status, 400);
  assertEquals((await send({ signed_transaction: 5 })).status, 400);
});

Deno.test("database failure answers 500", async () => {
  const { store, send } = setup();
  store.fail = true;
  assertEquals((await send({ signed_transaction: await chain.sign(tx()) })).status, 500);
});

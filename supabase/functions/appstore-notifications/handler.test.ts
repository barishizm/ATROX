import { FakeAppStoreStore } from "../_shared/appstore/fake-store.ts";
import { createJwsVerifier } from "../_shared/appstore/jws.ts";
import { type FakeAppleChain, fakeAppleChain } from "../_shared/appstore/test-chain.ts";
import { parseEnvironments, type TransactionInfo } from "../_shared/appstore/entitlement.ts";
import { assert, assertEquals } from "../_shared/testing.ts";
import { createNotificationsHandler } from "./handler.ts";

const NOW = Date.UTC(2026, 10, 14, 12);
const DAY = 86_400_000;
const TOKEN = "b74ace79-3051-5fbe-8b18-7a4c598b8ebf"; // AppAccountToken of user 00000000-…-0001 (iOS known vector)
const USER = "00000000-0000-0000-0000-000000000001";
const chain: FakeAppleChain = await fakeAppleChain();
let counter = 0;

function tx(over: Partial<TransactionInfo> = {}): TransactionInfo {
  return {
    transactionId: "2000", originalTransactionId: "1000", productId: "atrox.pro.yearly", bundleId: "com.barishizm.atrox",
    purchaseDate: NOW - DAY, expiresDate: NOW + 364 * DAY, appAccountToken: TOKEN, environment: "Sandbox",
    signedDate: NOW + counter, ...over,
  };
}

async function notification(type: string, options: {
  subtype?: string; tx?: TransactionInfo | null; renewal?: Record<string, unknown>; uuid?: string; environment?: string;
  bundleId?: string; signer?: FakeAppleChain;
} = {}) {
  counter += 1;
  const signer = options.signer ?? chain;
  const data: Record<string, unknown> = {
    bundleId: options.bundleId ?? "com.barishizm.atrox", environment: options.environment ?? "Sandbox",
  };
  if (options.tx !== null) data.signedTransactionInfo = await signer.sign(options.tx ?? tx());
  if (options.renewal) data.signedRenewalInfo = await signer.sign({ signedDate: NOW, ...options.renewal });
  const payload = {
    notificationType: type, subtype: options.subtype, version: "2.0", signedDate: NOW + counter,
    notificationUUID: options.uuid ?? crypto.randomUUID(), data,
  };
  return { signedPayload: await signer.sign(payload) };
}

function setup(environments = "Production,Sandbox") {
  const store = new FakeAppStoreStore({ [TOKEN]: USER });
  const handler = createNotificationsHandler({
    verifyJws: createJwsVerifier({ roots: [chain.root], now: () => NOW }),
    store, bundleIds: new Set(["com.barishizm.atrox"]), environments: parseEnvironments(environments), now: () => NOW,
  });
  const send = async (body: unknown) => {
    const response = await handler(new Request("http://x/appstore-notifications", { method: "POST", body: JSON.stringify(body) }));
    return { status: response.status, body: await response.json() };
  };
  return { store, send };
}

Deno.test("SUBSCRIBED creates an active row for the token's user", async () => {
  const { store, send } = setup();
  const res = await send(await notification("SUBSCRIBED", { subtype: "INITIAL_BUY", renewal: { autoRenewStatus: 1 } }));
  assertEquals(res, { status: 200, body: { matched: true, applied: true, status: "active" } });
  assertEquals(store.rows.length, 1);
  assertEquals(store.rows[0].user_id, USER);
  assertEquals(store.rows[0].environment, "sandbox");
  assertEquals(store.rows[0].will_renew, true);
  assertEquals(store.events[0].matched, true);
});

Deno.test("an introductory free trial is stored as trial", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED", { tx: tx({ offerType: 1, offerDiscountType: "FREE_TRIAL", expiresDate: NOW + 7 * DAY }) }));
  assertEquals(store.rows[0].status, "trial");
});

Deno.test("DID_RENEW moves the expiry forward", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED"));
  await send(await notification("DID_RENEW", { tx: tx({ transactionId: "2001", expiresDate: NOW + 729 * DAY }) }));
  assertEquals(store.rows.length, 1);
  assertEquals(store.rows[0].status, "active");
  assertEquals(store.rows[0].expires_at, new Date(NOW + 729 * DAY).toISOString());
});

Deno.test("EXPIRED ends access", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED"));
  await send(await notification("EXPIRED", { subtype: "VOLUNTARY", tx: tx({ expiresDate: NOW - 1000 }), renewal: { autoRenewStatus: 0 } }));
  assertEquals(store.rows[0].status, "expired");
  assertEquals(store.rows[0].will_renew, false);
});

Deno.test("REFUND and REVOKE end access at the revocation date", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED"));
  await send(await notification("REFUND", { tx: tx({ revocationDate: NOW - 5000, revocationReason: 0 }) }));
  assertEquals(store.rows[0].status, "refunded");
  assertEquals(store.rows[0].expires_at, new Date(NOW - 5000).toISOString());
  await send(await notification("REVOKE", { tx: tx({ revocationDate: NOW - 4000 }) }));
  assertEquals(store.rows[0].status, "revoked");
});

Deno.test("DID_FAIL_TO_RENEW: grace period keeps access until its end, otherwise billing retry", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED"));
  const lapsed = tx({ expiresDate: NOW - 1000 });
  await send(await notification("DID_FAIL_TO_RENEW", {
    subtype: "GRACE_PERIOD", tx: lapsed, renewal: { gracePeriodExpiresDate: NOW + 6 * DAY, isInBillingRetryPeriod: true, autoRenewStatus: 1 },
  }));
  assertEquals(store.rows[0].status, "grace_period");
  assertEquals(store.rows[0].expires_at, new Date(NOW + 6 * DAY).toISOString());
  await send(await notification("GRACE_PERIOD_EXPIRED", { tx: lapsed, renewal: { isInBillingRetryPeriod: true } }));
  assertEquals(store.rows[0].status, "billing_retry");
  await send(await notification("DID_FAIL_TO_RENEW", { tx: lapsed, renewal: { isInBillingRetryPeriod: true } }));
  assertEquals(store.rows[0].status, "billing_retry");
});

Deno.test("DID_CHANGE_RENEWAL_STATUS keeps access and records will_renew", async () => {
  const { store, send } = setup();
  await send(await notification("SUBSCRIBED"));
  await send(await notification("DID_CHANGE_RENEWAL_STATUS", { subtype: "AUTO_RENEW_DISABLED", renewal: { autoRenewStatus: 0 } }));
  assertEquals(store.rows[0].status, "active");
  assertEquals(store.rows[0].will_renew, false);
});

Deno.test("a repeated notification UUID is applied once", async () => {
  const { store, send } = setup();
  const uuid = crypto.randomUUID();
  await send(await notification("SUBSCRIBED", { uuid }));
  const again = await send(await notification("EXPIRED", { uuid, tx: tx({ expiresDate: NOW - 1 }) }));
  assertEquals(again, { status: 200, body: { duplicate: true } });
  assertEquals(store.rows[0].status, "active");
  assertEquals(store.events.length, 1);
});

Deno.test("an older payload does not overwrite a newer one (out-of-order delivery)", async () => {
  const { store, send } = setup();
  await send(await notification("EXPIRED", { tx: tx({ expiresDate: NOW - 1, signedDate: NOW + 10_000 }) }));
  const res = await send(await notification("DID_RENEW", { tx: tx({ signedDate: NOW - 10_000 }) }));
  assertEquals(res.body.applied, false);
  assertEquals(store.rows[0].status, "expired");
});

Deno.test("invalid signatures are rejected without touching the store", async () => {
  const { store, send } = setup();
  const stranger = await fakeAppleChain();
  const res = await send(await notification("SUBSCRIBED", { signer: stranger }));
  assertEquals(res.status, 401);
  assertEquals(res.body.reason, "untrusted_root");
  const good = await notification("SUBSCRIBED");
  const [h, p] = good.signedPayload.split(".");
  assertEquals((await send({ signedPayload: `${h}.${p}.AAAA` })).status, 401);
  // A valid envelope carrying a forged transaction is rejected too.
  const forgedTx = await stranger.sign(tx());
  const envelope = await chain.sign({
    notificationType: "SUBSCRIBED", notificationUUID: crypto.randomUUID(), signedDate: NOW,
    data: { bundleId: "com.barishizm.atrox", environment: "Sandbox", signedTransactionInfo: forgedTx },
  });
  assertEquals((await send({ signedPayload: envelope })).status, 401);
  assertEquals(store.rows.length, 0);
  assertEquals(store.events.length, 0);
});

Deno.test("an unknown token is recorded as unmatched; a known transaction still finds its owner", async () => {
  const { store, send } = setup();
  const res = await send(await notification("SUBSCRIBED", { tx: tx({ appAccountToken: crypto.randomUUID(), originalTransactionId: "9" }) }));
  assertEquals(res.body.matched, false);
  assertEquals(store.rows.length, 0);
  assertEquals(store.events[0].matched, false);
  assertEquals(store.events[0].reason, "unknown_token");
  await send(await notification("SUBSCRIBED"));
  await send(await notification("DID_RENEW", { tx: tx({ appAccountToken: undefined, expiresDate: NOW + 800 * DAY }) }));
  assertEquals(store.rows[0].expires_at, new Date(NOW + 800 * DAY).toISOString());
});

Deno.test("staging accepts Sandbox only; production rows and sandbox rows stay apart", async () => {
  const staging = setup("Sandbox");
  const res = await staging.send(await notification("SUBSCRIBED", { environment: "Production", tx: tx({ environment: "Production" }) }));
  assertEquals(res.body, { ignored: "environment_not_accepted" });
  assertEquals(staging.store.rows.length, 0);

  const prod = setup();
  await prod.send(await notification("SUBSCRIBED"));
  await prod.send(await notification("SUBSCRIBED", { environment: "Production", tx: tx({ environment: "Production" }) }));
  assertEquals(prod.store.rows.map((r) => r.environment).sort(), ["production", "sandbox"]);
  const mixed = await prod.send(await notification("DID_RENEW", { environment: "Production", tx: tx({ environment: "Sandbox" }) }));
  assertEquals(mixed.body, { ignored: "environment_mismatch" });
});

Deno.test("TEST and other types without a transaction are acknowledged and recorded", async () => {
  const { store, send } = setup();
  const res = await send(await notification("TEST", { tx: null }));
  assertEquals(res.body, { ignored: "no_subscription_change" });
  assertEquals(store.events.length, 1);
  assertEquals(store.rows.length, 0);
});

Deno.test("wrong bundle or unknown product is ignored", async () => {
  const { store, send } = setup();
  assertEquals((await send(await notification("SUBSCRIBED", { bundleId: "com.other.app" }))).body, { ignored: "wrong_bundle" });
  assertEquals((await send(await notification("SUBSCRIBED", { tx: tx({ productId: "other.product" }) }))).body, { ignored: "unknown_product" });
  assertEquals(store.rows.length, 0);
});

Deno.test("bad requests and database failures", async () => {
  const { store, send } = setup();
  assertEquals((await send({})).status, 400);
  assertEquals((await send({ signedPayload: 3 })).status, 400);
  store.fail = true;
  const res = await send(await notification("SUBSCRIBED"));
  assertEquals(res.status, 500);
  assert(store.rows.length === 0);
});

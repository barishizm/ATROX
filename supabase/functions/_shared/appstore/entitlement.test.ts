import { assertEquals } from "../testing.ts";
import { deriveStatus, parseEnvironments, statusForNotification, willRenew } from "./entitlement.ts";

const NOW = 1_000_000;

Deno.test("deriveStatus follows the transaction and renewal info", () => {
  assertEquals(deriveStatus({ expiresDate: NOW + 1 }, undefined, NOW).status, "active");
  assertEquals(deriveStatus({ expiresDate: NOW + 1, offerType: 1, offerDiscountType: "FREE_TRIAL" }, undefined, NOW).status, "trial");
  assertEquals(deriveStatus({ expiresDate: NOW + 1, offerType: 1, offerDiscountType: "PAY_AS_YOU_GO" }, undefined, NOW).status, "active");
  assertEquals(deriveStatus({ expiresDate: NOW - 1 }, { gracePeriodExpiresDate: NOW + 5 }, NOW), { status: "grace_period", expiresMs: NOW + 5 });
  assertEquals(deriveStatus({ expiresDate: NOW - 1 }, { isInBillingRetryPeriod: true }, NOW).status, "billing_retry");
  assertEquals(deriveStatus({ expiresDate: NOW - 1 }, undefined, NOW).status, "expired");
  assertEquals(deriveStatus({ expiresDate: NOW + 1, revocationDate: NOW - 2 }, undefined, NOW), { status: "refunded", expiresMs: NOW - 2 });
});

Deno.test("explicit lifecycle events win over the clock", () => {
  assertEquals(statusForNotification("EXPIRED", "VOLUNTARY", { expiresDate: NOW + 1 }, undefined, NOW).status, "expired");
  assertEquals(statusForNotification("DID_FAIL_TO_RENEW", undefined, { expiresDate: NOW - 1 }, undefined, NOW).status, "billing_retry");
  assertEquals(statusForNotification("REFUND_REVERSED", undefined, { expiresDate: NOW + 1 }, undefined, NOW).status, "active");
});

Deno.test("willRenew and environments", () => {
  assertEquals(willRenew("active", { autoRenewStatus: 0 }), false);
  assertEquals(willRenew("active", undefined), true);
  assertEquals(willRenew("expired", { autoRenewStatus: 1 }), false);
  assertEquals([...parseEnvironments("Sandbox")], ["sandbox"]);
  assertEquals([...parseEnvironments(undefined)], ["production", "sandbox"]);
  assertEquals([...parseEnvironments("Xcode, Sandbox")], ["sandbox"]);
});

// appstore-notifications (P090): App Store Server Notifications V2 endpoint. Apple POSTs { signedPayload }.
//   1. POST + JSON with a signedPayload string                      → 405 / 400
//   2. JWS verified against the Apple root chain                    → 401 invalid signature
//   3. environment accepted here (staging: Sandbox only), bundle ID → 200 { ignored } (recorded, Apple stops retrying)
//   4. notificationUUID seen before                                  → 200 { duplicate: true } (idempotent)
//   5. types without a subscription change (TEST, …)                 → 200 { ignored } (recorded)
//   6. signedTransactionInfo / signedRenewalInfo verified + mapped   → entitlements via appstore_apply
//   7. no user for the transaction (no/unknown appAccountToken)      → 200, recorded as unmatched + warning log
// A database failure answers 500 so Apple retries later.
import {
  type AppStoreEnvironment,
  type AppStoreStore,
  environmentOf,
  IGNORED_TYPES,
  isUuid,
  type NotificationPayload,
  rejectTransaction,
  type RenewalInfo,
  statusForNotification,
  toState,
  type TransactionInfo,
} from "../_shared/appstore/entitlement.ts";
import { JwsError, type JwsVerifier } from "../_shared/appstore/jws.ts";

export interface NotificationsDeps {
  verifyJws: JwsVerifier;
  store: AppStoreStore;
  bundleIds: Set<string>;
  environments: Set<AppStoreEnvironment>;
  now?: () => number;
}

const MAX_BODY = 64 * 1024;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

export function createNotificationsHandler(deps: NotificationsDeps) {
  const now = deps.now ?? Date.now;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    let signedPayload: unknown;
    try {
      const text = await request.text();
      if (text.length > MAX_BODY) return json({ error: "too_large" }, 413);
      signedPayload = (JSON.parse(text) as { signedPayload?: unknown }).signedPayload;
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    if (typeof signedPayload !== "string") return json({ error: "missing_signed_payload" }, 400);

    let payload: NotificationPayload;
    try {
      payload = await deps.verifyJws<NotificationPayload>(signedPayload);
    } catch (error) {
      const reason = error instanceof JwsError ? error.reason : "invalid";
      console.warn("appstore-notifications: rejected payload", reason);
      return json({ error: "invalid_signature", reason }, 401);
    }

    const uuid = isUuid(payload.notificationUUID) ? payload.notificationUUID.toLowerCase() : null;
    const type = typeof payload.notificationType === "string" ? payload.notificationType : null;
    if (!uuid || !type) return json({ error: "invalid_payload" }, 400);
    const subtype = typeof payload.subtype === "string" ? payload.subtype : null;
    const environment = environmentOf(payload.data?.environment);
    const event = {
      source: "notification" as const,
      notification_uuid: uuid,
      notification_type: type,
      subtype,
      environment,
      original_transaction_id: null as string | null,
      user_id: null as string | null,
      matched: false,
      reason: null as string | null,
      signed_at: typeof payload.signedDate === "number" ? new Date(payload.signedDate).toISOString() : null,
    };

    try {
      if (await deps.store.notificationSeen(uuid)) return json({ duplicate: true });

      const ignore = async (reason: string, matched = false) => {
        await deps.store.recordEvent({ ...event, matched, reason });
        return json({ ignored: reason });
      };
      if (!environment) return await ignore("unknown_environment");
      if (!deps.environments.has(environment)) {
        console.warn("appstore-notifications: environment not accepted here", environment);
        return await ignore("environment_not_accepted");
      }
      if (!payload.data?.bundleId || !deps.bundleIds.has(payload.data.bundleId)) return await ignore("wrong_bundle");
      const signedTx = payload.data.signedTransactionInfo;
      if (IGNORED_TYPES.has(type) || typeof signedTx !== "string") return await ignore("no_subscription_change", true);

      let tx: TransactionInfo;
      let renewal: RenewalInfo | undefined;
      try {
        tx = await deps.verifyJws<TransactionInfo>(signedTx);
        const signedRenewal = payload.data.signedRenewalInfo;
        renewal = typeof signedRenewal === "string" ? await deps.verifyJws<RenewalInfo>(signedRenewal) : undefined;
      } catch (error) {
        const reason = error instanceof JwsError ? error.reason : "invalid";
        console.warn("appstore-notifications: rejected transaction", reason);
        return json({ error: "invalid_signature", reason }, 401);
      }
      event.original_transaction_id = tx.originalTransactionId ?? null;
      const rejected = rejectTransaction(tx, deps.bundleIds, deps.environments);
      if (rejected) return await ignore(rejected);
      if (environmentOf(tx.environment) !== environment) return await ignore("environment_mismatch");

      const nowMs = now();
      const state = toState(tx, environment, statusForNotification(type, subtype ?? undefined, tx, renewal, nowMs), renewal, nowMs);
      const result = await deps.store.apply(null, state);
      if (!result.matched) {
        console.warn("appstore-notifications: transaction matched no user", {
          type, original_transaction_id: state.original_transaction_id, reason: result.reason,
        });
      }
      await deps.store.recordEvent({ ...event, user_id: result.user_id, matched: result.matched, reason: result.reason });
      return json({ matched: result.matched, applied: result.applied, status: state.status });
    } catch (error) {
      console.error("appstore-notifications failed", error instanceof Error ? error.message : error);
      return json({ error: "internal" }, 500);
    }
  };
}

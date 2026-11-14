// verify-purchase (P090): the app sends a StoreKit 2 transaction (`jwsRepresentation`) right after a purchase or
// restore; the function verifies it and writes the entitlement at once, without waiting for Apple's notification.
//   1. JWT, body { signed_transaction }                          → 401 / 400
//   2. JWS verified against the Apple root chain                  → 400 invalid_request (details.reason)
//   3. bundle ID, environment (staging: Sandbox only), product     → 400 invalid_request (details.reason)
//   4. appAccountToken must be the caller's; the transaction must
//      not already belong to another account                       → 409 account_mismatch (recorded + warning log)
//   5. appstore_apply                                              → 200 { is_pro, status, expires_at, product_id }
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import {
  type AppStoreEnvironment,
  type AppStoreStore,
  deriveStatus,
  environmentOf,
  rejectTransaction,
  toState,
  type TransactionInfo,
} from "../_shared/appstore/entitlement.ts";
import { JwsError, type JwsVerifier } from "../_shared/appstore/jws.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";

export interface VerifyPurchaseDeps {
  verify: TokenVerifier;
  verifyJws: JwsVerifier;
  store: AppStoreStore;
  bundleIds: Set<string>;
  environments: Set<AppStoreEnvironment>;
  now?: () => number;
}

const MAX_JWS = 16 * 1024;
const PRO_STATUSES = new Set(["active", "trial", "grace_period"]);

const json = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });

export function createVerifyPurchaseHandler(deps: VerifyPurchaseDeps) {
  const now = deps.now ?? Date.now;
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();
    if (request.method !== "POST") return errorResponse("method_not_allowed", "Use POST.");
    const auth = await requireUser(request, deps.verify);
    if (auth instanceof Response) return auth;

    let jws: unknown;
    try {
      const body = await request.json() as Record<string, unknown>;
      if (!body || typeof body !== "object" || Object.keys(body).some((key) => key !== "signed_transaction")) throw new Error();
      jws = body.signed_transaction;
    } catch {
      return errorResponse("invalid_request", "Body must be { signed_transaction }.");
    }
    if (typeof jws !== "string" || jws.length === 0 || jws.length > MAX_JWS) {
      return errorResponse("invalid_request", "signed_transaction must be a JWS string.");
    }

    let tx: TransactionInfo;
    try {
      tx = await deps.verifyJws<TransactionInfo>(jws);
    } catch (error) {
      return errorResponse("invalid_request", "The transaction signature is not valid.", {
        reason: error instanceof JwsError ? error.reason : "invalid",
      });
    }
    const rejected = rejectTransaction(tx, deps.bundleIds, deps.environments);
    if (rejected) return errorResponse("invalid_request", "The transaction cannot be used here.", { reason: rejected });

    const nowMs = now();
    const environment = environmentOf(tx.environment)!;
    const state = toState(tx, environment, deriveStatus(tx, undefined, nowMs), undefined, nowMs);
    try {
      const result = await deps.store.apply(auth.userId, state);
      await deps.store.recordEvent({
        source: "verify", notification_uuid: null, notification_type: null, subtype: null, environment,
        original_transaction_id: state.original_transaction_id, user_id: auth.userId, matched: result.matched,
        reason: result.reason, signed_at: state.signed_at,
      });
      if (!result.matched) {
        console.warn("verify-purchase: transaction does not belong to the caller", {
          original_transaction_id: state.original_transaction_id, reason: result.reason,
        });
        return errorResponse("account_mismatch", "This purchase belongs to another account.", { reason: result.reason });
      }
      const isPro = PRO_STATUSES.has(state.status) && (state.expires_at === null || Date.parse(state.expires_at) > nowMs);
      return json({ is_pro: isPro, status: state.status, expires_at: state.expires_at, product_id: state.product_id, applied: result.applied });
    } catch (error) {
      console.error("verify-purchase failed", error instanceof Error ? error.message : error);
      return errorResponse("internal", "Could not record the purchase.");
    }
  };
}

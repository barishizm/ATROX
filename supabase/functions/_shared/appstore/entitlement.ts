// App Store payloads → entitlements rows (P090). Pure functions; the handlers verify signatures first.
// Field names follow Apple's JWSTransactionDecodedPayload / JWSRenewalInfoDecodedPayload / ResponseBodyV2DecodedPayload.

export const PRO_PRODUCTS = ["atrox.pro.yearly", "atrox.pro.monthly"] as const;

export type EntitlementStatus =
  | "active"
  | "trial"
  | "grace_period"
  | "billing_retry"
  | "expired"
  | "refunded"
  | "revoked";

export type AppStoreEnvironment = "sandbox" | "production";

export interface TransactionInfo {
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  bundleId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  appAccountToken?: string;
  environment?: string;
  revocationDate?: number;
  revocationReason?: number;
  /** 1 introductory offer, 2 promotional, 3 offer code, 4 win-back. */
  offerType?: number;
  offerDiscountType?: string;
  signedDate?: number;
}

export interface RenewalInfo {
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
  signedDate?: number;
}

export interface NotificationPayload {
  notificationType?: string;
  subtype?: string;
  notificationUUID?: string;
  signedDate?: number;
  version?: string;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    status?: number;
  };
}

export interface EntitlementState {
  product_id: string;
  status: EntitlementStatus;
  expires_at: string | null;
  original_transaction_id: string;
  environment: AppStoreEnvironment;
  will_renew: boolean;
  signed_at: string;
  app_account_token: string | null;
}

/** Notification types that carry no subscription change for us; they are recorded and acknowledged. */
export const IGNORED_TYPES = new Set([
  "TEST",
  "CONSUMPTION_REQUEST",
  "PRICE_INCREASE",
  "RENEWAL_EXTENSION",
  "EXTERNAL_PURCHASE_TOKEN",
  "ONE_TIME_CHARGE",
  "METADATA_UPDATE",
  "MIGRATION",
  "RESCIND_CONSENT",
]);

export function environmentOf(raw: unknown): AppStoreEnvironment | null {
  if (raw === "Sandbox") return "sandbox";
  if (raw === "Production") return "production";
  return null;
}

/** "Production,Sandbox" → set of environments (unknown names dropped). */
export function parseEnvironments(raw: string | undefined): Set<AppStoreEnvironment> {
  const list = (raw ?? "Production,Sandbox").split(",").map((part) => environmentOf(part.trim()));
  return new Set(list.filter((env): env is AppStoreEnvironment => env !== null));
}

const iso = (ms: number | undefined) => (typeof ms === "number" ? new Date(ms).toISOString() : null);

/** The state a transaction (+ renewal info) describes at `nowMs`, without any notification hint. */
export function deriveStatus(
  tx: TransactionInfo,
  renewal: RenewalInfo | undefined,
  nowMs: number,
): { status: EntitlementStatus; expiresMs: number | undefined } {
  if (typeof tx.revocationDate === "number") return { status: "refunded", expiresMs: tx.revocationDate };
  const expires = tx.expiresDate;
  if (expires === undefined || expires > nowMs) {
    const trial = tx.offerType === 1 && (tx.offerDiscountType === undefined || tx.offerDiscountType === "FREE_TRIAL");
    return { status: trial ? "trial" : "active", expiresMs: expires };
  }
  const grace = renewal?.gracePeriodExpiresDate;
  if (typeof grace === "number" && grace > nowMs) return { status: "grace_period", expiresMs: grace };
  if (renewal?.isInBillingRetryPeriod) return { status: "billing_retry", expiresMs: expires };
  return { status: "expired", expiresMs: expires };
}

/**
 * The status a notification implies. Explicit lifecycle events win over the clock (an EXPIRED notification can arrive a
 * second before expiresDate by our clock); the rest follow the signed transaction.
 */
export function statusForNotification(
  type: string,
  subtype: string | undefined,
  tx: TransactionInfo,
  renewal: RenewalInfo | undefined,
  nowMs: number,
): { status: EntitlementStatus; expiresMs: number | undefined } {
  const derived = deriveStatus(tx, renewal, nowMs);
  switch (type) {
    case "REFUND":
      return { status: "refunded", expiresMs: tx.revocationDate ?? derived.expiresMs };
    case "REVOKE":
      return { status: "revoked", expiresMs: tx.revocationDate ?? derived.expiresMs };
    case "EXPIRED":
      return { status: "expired", expiresMs: tx.expiresDate };
    case "GRACE_PERIOD_EXPIRED":
      return { status: "billing_retry", expiresMs: tx.expiresDate };
    case "DID_FAIL_TO_RENEW":
      if (subtype === "GRACE_PERIOD" && typeof renewal?.gracePeriodExpiresDate === "number") {
        return { status: "grace_period", expiresMs: renewal.gracePeriodExpiresDate };
      }
      return derived.status === "active" || derived.status === "trial" ? derived : { status: "billing_retry", expiresMs: tx.expiresDate };
    default:
      // SUBSCRIBED, DID_RENEW, DID_CHANGE_RENEWAL_STATUS / _PREF, OFFER_REDEEMED, RENEWAL_EXTENDED, REFUND_REVERSED,
      // REFUND_DECLINED, …: the transaction itself is the truth.
      return derived;
  }
}

export function willRenew(status: EntitlementStatus, renewal: RenewalInfo | undefined): boolean {
  if (status === "expired" || status === "refunded" || status === "revoked") return false;
  if (renewal && typeof renewal.autoRenewStatus === "number") return renewal.autoRenewStatus === 1;
  return status === "active" || status === "trial";
}

export function toState(
  tx: TransactionInfo,
  environment: AppStoreEnvironment,
  result: { status: EntitlementStatus; expiresMs: number | undefined },
  renewal: RenewalInfo | undefined,
  nowMs: number,
): EntitlementState {
  return {
    product_id: tx.productId!,
    status: result.status,
    expires_at: iso(result.expiresMs),
    original_transaction_id: tx.originalTransactionId!,
    environment,
    will_renew: willRenew(result.status, renewal),
    signed_at: iso(tx.signedDate ?? nowMs)!,
    app_account_token: isUuid(tx.appAccountToken) ? tx.appAccountToken!.toLowerCase() : null,
  };
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

/** Why a verified transaction cannot be used, or null. */
export function rejectTransaction(
  tx: TransactionInfo,
  bundleIds: Set<string>,
  environments: Set<AppStoreEnvironment>,
): string | null {
  if (!tx.bundleId || !bundleIds.has(tx.bundleId)) return "wrong_bundle";
  const env = environmentOf(tx.environment);
  if (!env) return "unknown_environment";
  if (!environments.has(env)) return "environment_not_accepted";
  if (!tx.productId || !(PRO_PRODUCTS as readonly string[]).includes(tx.productId)) return "unknown_product";
  if (!tx.originalTransactionId) return "missing_transaction_id";
  return null;
}

/** Result of `appstore_apply`. */
export interface ApplyResult {
  matched: boolean;
  reason: string | null;
  user_id: string | null;
  applied: boolean;
}

/** What both handlers need from the database; `index.ts` implements it with supabase-js, tests with a fake. */
export interface AppStoreStore {
  notificationSeen(uuid: string): Promise<boolean>;
  apply(userId: string | null, state: EntitlementState): Promise<ApplyResult>;
  recordEvent(event: {
    source: "notification" | "verify";
    notification_uuid: string | null;
    notification_type: string | null;
    subtype: string | null;
    environment: AppStoreEnvironment | null;
    original_transaction_id: string | null;
    user_id: string | null;
    matched: boolean;
    reason: string | null;
    signed_at: string | null;
  }): Promise<void>;
}

/** Reads the shared configuration from the environment. */
export function appStoreConfig(env: (name: string) => string | undefined) {
  const bundleIds = new Set((env("APPSTORE_BUNDLE_IDS") ?? "com.barishizm.atrox").split(",").map((s) => s.trim()).filter(Boolean));
  return { bundleIds, environments: parseEnvironments(env("APPSTORE_ENVIRONMENTS")) };
}

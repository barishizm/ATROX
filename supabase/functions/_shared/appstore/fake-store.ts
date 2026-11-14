// Test-only in-memory AppStoreStore that follows appstore_apply's rules (schema_20).
import type { AppStoreStore, ApplyResult, EntitlementState } from "./entitlement.ts";

export interface FakeRow extends EntitlementState {
  user_id: string;
}

export class FakeAppStoreStore implements AppStoreStore {
  rows: FakeRow[] = [];
  events: Parameters<AppStoreStore["recordEvent"]>[0][] = [];
  fail = false;

  constructor(public tokens: Record<string, string> = {}) {}

  notificationSeen(uuid: string) {
    if (this.fail) return Promise.reject(new Error("db down"));
    return Promise.resolve(this.events.some((e) => e.notification_uuid === uuid));
  }

  apply(userId: string | null, state: EntitlementState): Promise<ApplyResult> {
    if (this.fail) return Promise.reject(new Error("db down"));
    const tokenUser = state.app_account_token ? this.tokens[state.app_account_token] ?? null : null;
    const existing = this.rows.find((r) => r.original_transaction_id === state.original_transaction_id && r.environment === state.environment);
    const no = (reason: string): ApplyResult => ({ matched: false, reason, user_id: null, applied: false });
    let user: string;
    if (userId) {
      if (state.app_account_token && tokenUser !== userId) return Promise.resolve(no("token_mismatch"));
      if (existing && existing.user_id !== userId) return Promise.resolve(no("owned_by_other"));
      user = userId;
    } else {
      const found = tokenUser ?? existing?.user_id;
      if (!found) return Promise.resolve(no(state.app_account_token ? "unknown_token" : "no_token"));
      user = found;
    }
    if (!existing) {
      this.rows.push({ ...state, user_id: user });
      return Promise.resolve({ matched: true, reason: null, user_id: user, applied: true });
    }
    if (Date.parse(state.signed_at) < Date.parse(existing.signed_at)) {
      return Promise.resolve({ matched: true, reason: null, user_id: user, applied: false });
    }
    Object.assign(existing, { ...state, user_id: existing.user_id });
    return Promise.resolve({ matched: true, reason: null, user_id: user, applied: true });
  }

  recordEvent(event: Parameters<AppStoreStore["recordEvent"]>[0]) {
    if (this.fail) return Promise.reject(new Error("db down"));
    if (!event.notification_uuid || !this.events.some((e) => e.notification_uuid === event.notification_uuid)) this.events.push(event);
    return Promise.resolve();
  }
}

// AppStoreStore over the service-role RPCs of migration schema_20 (P090). Takes any supabase-js-like client.
import type { AppStoreStore, ApplyResult } from "./entitlement.ts";

interface RpcClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

export function rpcAppStoreStore(client: RpcClient): AppStoreStore {
  const call = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await client.rpc(fn, args);
    if (error) throw new Error(`${fn}: ${error.message}`);
    return data;
  };
  return {
    async notificationSeen(uuid) {
      return (await call("appstore_notification_seen", { p_uuid: uuid })) === true;
    },
    async apply(userId, state) {
      return await call("appstore_apply", {
        p_user: userId,
        p_token: state.app_account_token,
        p_product: state.product_id,
        p_status: state.status,
        p_expires_at: state.expires_at,
        p_original_transaction_id: state.original_transaction_id,
        p_environment: state.environment,
        p_will_renew: state.will_renew,
        p_signed_at: state.signed_at,
      }) as ApplyResult;
    },
    async recordEvent(event) {
      await call("appstore_record_event", {
        p_source: event.source,
        p_uuid: event.notification_uuid,
        p_type: event.notification_type,
        p_subtype: event.subtype,
        p_environment: event.environment,
        p_original_transaction_id: event.original_transaction_id,
        p_user: event.user_id,
        p_matched: event.matched,
        p_reason: event.reason,
        p_signed_at: event.signed_at,
      });
    },
  };
}

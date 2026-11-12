import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { type Row, type UserDataStore, type UserTable } from "./user-data.ts";

const PAGE = 1000;

/** `UserDataStore` with the service role (the functions filter by user id themselves). */
export function supabaseStore(): UserDataStore {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing");
  const admin: SupabaseClient = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  return {
    async userIdFromToken(jwt) {
      const { data, error } = await admin.auth.getUser(jwt);
      return error || !data.user ? null : data.user.id;
    },
    async rows(table: UserTable, userId: string) {
      const all: Row[] = [];
      for (let from = 0;; from += PAGE) {
        const { data, error } = await admin.from(table).select("*").eq("user_id", userId)
          .order("created_at", { ascending: true }).order("id", { ascending: true }).range(from, from + PAGE - 1);
        if (error) throw new Error(`${table}: ${error.message}`);
        all.push(...(data ?? []));
        if (!data || data.length < PAGE) return all;
      }
    },
    async deleteRows(table: UserTable, userId: string) {
      const { error } = await admin.from(table).delete().eq("user_id", userId);
      if (error) throw new Error(`${table}: ${error.message}`);
    },
    async deleteAuthUser(userId: string) {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw new Error(`auth: ${error.message}`);
    },
  };
}

import { createClient } from "@supabase/supabase-js";
import { type ContributionRow, createContributeHandler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing");

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

Deno.serve(createContributeHandler({
  verify: async (jwt) => {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data.user ? null : data.user.id;
  },
  async hit(userId, action, limit, windowSeconds) {
    const { error } = await admin.rpc("social_hit", {
      p_user: userId, p_bucket: action, p_limit: limit, p_window: `${windowSeconds} seconds`,
    });
    if (!error) return true;
    if (error.message.includes("rate_limited")) return false;
    throw new Error(`rate limit: ${error.message}`);
  },
  store: {
    async upsert(rows: ContributionRow[]) {
      const { error } = await admin.from("ml_contributions").upsert(rows, { onConflict: "contribution_key,month,exercise_id" });
      if (error) throw new Error(`upsert: ${error.message}`);
    },
    async remove(contributionKey: string) {
      const { data, error } = await admin.from("ml_contributions").delete().eq("contribution_key", contributionKey).select("id");
      if (error) throw new Error(`delete: ${error.message}`);
      return data?.length ?? 0;
    },
  },
}));

import { createClient } from "@supabase/supabase-js";
import { createPublishHandler, type PublishFacts } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing");

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

Deno.serve(createPublishHandler({
  verify: async (jwt) => {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data.user ? null : data.user.id;
  },
  service: {
    async facts(userId) {
      const { data, error } = await admin.rpc("social_publish_facts", { p_user: userId });
      if (error) throw new Error(`social_publish_facts: ${error.message}`);
      const row = (Array.isArray(data) ? data[0] : data) as PublishFacts | undefined;
      if (!row) throw new Error("social_publish_facts: empty");
      return row;
    },
    async hit(userId, action, limit, windowSeconds) {
      const { error } = await admin.rpc("social_hit", {
        p_user: userId, p_bucket: action, p_limit: limit, p_window: `${windowSeconds} seconds`,
      });
      if (!error) return true;
      if (error.message.includes("rate_limited")) return false;
      throw new Error(`social_hit: ${error.message}`);
    },
    async publish(userId, score, provisional, weekly) {
      const { error } = await admin.rpc("social_publish", {
        p_user: userId, p_score: score, p_provisional: provisional, p_weekly: weekly,
      });
      if (error) throw new Error(`social_publish: ${error.message}`);
    },
  },
}));

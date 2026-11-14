import { createClient } from "@supabase/supabase-js";
import { loadLLMConfig } from "../_shared/llm/config.ts";
import { deepSeekProvider, withRetry } from "../_shared/llm/providers.ts";
import { createCoachChatHandler, type QuotaDecision } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
if (!url || !serviceKey || !anonKey) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY missing");

const noSession = { persistSession: false, autoRefreshToken: false };
const admin = createClient(url, serviceKey, { auth: noSession });
const llm = loadLLMConfig();

function number(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

Deno.serve(createCoachChatHandler({
  verify: async (jwt) => {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data.user ? null : data.user.id;
  },
  // The caller's own JWT: every read and write below goes through RLS.
  userDb: (token) => {
    const client = createClient(url, anonKey, { auth: noSession, global: { headers: { Authorization: `Bearer ${token}` } } });
    return { rpc: async (fn, args) => {
      const { data, error } = await client.rpc(fn, args);
      return { data, error: error ? { message: error.message, code: error.code } : null };
    } };
  },
  service: {
    async consumeQuota(userId, timeZone) {
      const { data, error } = await admin.rpc("coach_consume_quota", { p_user: userId, p_time_zone: timeZone });
      if (error) throw new Error(`coach_consume_quota: ${error.message}`);
      return data as QuotaDecision;
    },
    async spendTodayUsd() {
      const { data, error } = await admin.rpc("coach_spend_today");
      if (error) throw new Error(`coach_spend_today: ${error.message}`);
      return Number(data ?? 0);
    },
    async recordUsage(rows) {
      const { error } = await admin.from("coach_usage").insert(rows);
      if (error) throw new Error(`coach_usage: ${error.message}`);
    },
  },
  provider: (onRetry) => withRetry(deepSeekProvider({ ...llm.deepseek, timeoutMs: llm.timeoutMs }), onRetry),
  settings: {
    consentVersion: Deno.env.get("COACH_AI_CONSENT_VERSION") || "2026-11",
    dailySpendCapUsd: number("COACH_DAILY_SPEND_CAP_USD", 25),
    turnTimeoutMs: number("COACH_TURN_TIMEOUT_MS", 60_000),
    maxOutputTokensCall: llm.maxOutputTokens,
    prices: llm.prices,
  },
}));

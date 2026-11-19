import { createClient } from "@supabase/supabase-js";
import { loadLLMConfig } from "../_shared/llm/config.ts";
import { deepSeekProvider, withRetry } from "../_shared/llm/providers.ts";
import { type UsageRow } from "../coach-chat/handler.ts";
import { type Allowance } from "../coach-digest/handler.ts";
import { createFoodHandler } from "./handler.ts";

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

Deno.serve(createFoodHandler({
  verify: async (jwt) => {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data.user ? null : data.user.id;
  },
  userDb: (token) => {
    const client = createClient(url, anonKey, { auth: noSession, global: { headers: { Authorization: `Bearer ${token}` } } });
    return { rpc: async (fn, args) => {
      const { data, error } = await client.rpc(fn, args);
      return { data, error: error ? { message: error.message, code: error.code } : null };
    } };
  },
  service: {
    async allowance(userId, timeZone) {
      const { data, error } = await admin.rpc("food_allowance", { p_user: userId, p_time_zone: timeZone });
      if (error) throw new Error(`food_allowance: ${error.message}`);
      return data as Allowance;
    },
    async spendTodayUsd() {
      const { data, error } = await admin.rpc("coach_spend_today");
      if (error) throw new Error(`coach_spend_today: ${error.message}`);
      return Number(data ?? 0);
    },
    async recordAnalysis(userId, kind) {
      const { error } = await admin.from("food_analyses").insert({ user_id: userId, kind });
      if (error) throw new Error(`food_analyses: ${error.message}`);
    },
    async recordUsage(rows: UsageRow[]) {
      const { error } = await admin.from("coach_usage").insert(rows);
      if (error) throw new Error(`coach_usage: ${error.message}`);
    },
  },
  provider: () => withRetry(deepSeekProvider({ ...llm.deepseek, timeoutMs: llm.timeoutMs })),
  settings: {
    consentVersion: Deno.env.get("FOOD_AI_CONSENT_VERSION") || "2026-11",
    dailySpendCapUsd: number("COACH_DAILY_SPEND_CAP_USD", 25),
    maxOutputTokens: 900,
    timeoutMs: number("FOOD_TIMEOUT_MS", 30_000),
    prices: llm.prices,
  },
}));

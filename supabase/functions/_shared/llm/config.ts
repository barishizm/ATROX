// Provider configuration from environment variables (docs/04-AI-KOC.md §3, docs/KURULUM.md "AI Koç anahtarları").
// Keys live only in Supabase Edge Function secrets; everything else has a working default.

export interface Price {
  /** USD per 1M uncached input tokens. */
  input: number;
  /** USD per 1M input tokens served from the provider's prompt cache. */
  cached_input: number;
  /** USD per 1M output tokens (reasoning tokens included). */
  output: number;
}

export interface LLMConfig {
  openrouter: { apiKey?: string; model: string; providers: string[]; baseUrl: string };
  deepseek: { apiKey?: string; model: string; baseUrl: string };
  /** Time allowed until the provider starts answering (headers received). */
  timeoutMs: number;
  maxOutputTokens: number;
  /** Keyed `provider:model`. */
  prices: Record<string, Price>;
}

/**
 * Defaults verified 2026-11-14 (docs/04-AI-KOC.md "Doğrulanmış API notları").
 * DeepSeek: peak-hour list price (off-peak is half), so the recorded cost is an upper bound.
 * OpenRouter: the price varies per upstream provider; the reported `usage.cost` wins when present.
 */
export const DEFAULT_PRICES: Record<string, Price> = {
  "openrouter:deepseek/deepseek-v4.1-flash": { input: 0.15, cached_input: 0.015, output: 0.60 },
  "deepseek:deepseek-flash": { input: 0.30, cached_input: 0.006, output: 1.20 },
};

type Env = (name: string) => string | undefined;

function positiveInt(env: Env, name: string, fallback: number): number {
  const value = Number(env(name));
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

export function loadLLMConfig(env: Env = (name) => Deno.env.get(name)): LLMConfig {
  let prices = DEFAULT_PRICES;
  const rawPrices = env("COACH_PRICES");
  if (rawPrices) {
    try {
      prices = { ...DEFAULT_PRICES, ...JSON.parse(rawPrices) };
    } catch {
      console.error("COACH_PRICES is not valid JSON; using defaults");
    }
  }
  return {
    openrouter: {
      apiKey: env("OPENROUTER_API_KEY") || undefined,
      model: env("COACH_OPENROUTER_MODEL") || "deepseek/deepseek-v4.1-flash",
      providers: (env("COACH_OPENROUTER_PROVIDERS") ?? "").split(",").map((slug) => slug.trim()).filter(Boolean),
      baseUrl: env("COACH_OPENROUTER_BASE_URL") || "https://openrouter.ai/api/v1",
    },
    deepseek: {
      apiKey: env("DEEPSEEK_API_KEY") || undefined,
      model: env("COACH_DEEPSEEK_MODEL") || "deepseek-flash",
      baseUrl: env("COACH_DEEPSEEK_BASE_URL") || "https://api.deepseek.com",
    },
    timeoutMs: positiveInt(env, "COACH_LLM_TIMEOUT_MS", 20_000),
    maxOutputTokens: positiveInt(env, "COACH_MAX_OUTPUT_TOKENS", 1_500),
    prices,
  };
}

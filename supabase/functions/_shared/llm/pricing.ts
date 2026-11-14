import { type Price } from "./config.ts";
import { type Usage } from "./types.ts";

/**
 * Cost of one call in USD, rounded to 6 decimals (the `coach_usage.cost_usd` scale).
 * The provider-reported cost wins; otherwise the configured price table; an unknown model costs 0 and is logged.
 */
export function costUsd(usage: Usage, provider: string, model: string, prices: Record<string, Price>): number {
  if (usage.reported_cost_usd !== undefined && usage.reported_cost_usd >= 0) return round6(usage.reported_cost_usd);
  const price = prices[`${provider}:${model}`];
  if (!price) {
    if (provider !== "fake") console.error(`no price configured for ${provider}:${model}`);
    return 0;
  }
  const cached = Math.min(usage.cached_tokens, usage.prompt_tokens);
  const uncached = usage.prompt_tokens - cached;
  return round6((uncached * price.input + cached * price.cached_input + usage.completion_tokens * price.output) / 1e6);
}

function round6(value: number): number {
  return Math.round(value * 1e6) / 1e6;
}

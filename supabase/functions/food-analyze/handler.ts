// food-analyze: estimates calories and macros from a meal photo or a text description.
//   1. JWT, input schema                                  → 401 / 400
//   2. current food_ai_sharing consent                     → 403 consent_required
//   3. global daily spend cap                              → 503 food_unavailable
//   4. take one analysis (free 3/day, Pro 60/day, 6/min)   → 429 quota_exceeded / rate_limited
//   5. one LLM call, JSON reply, thinking off              → 200 { meal_name, items, totals }
// Every call the model answered counts, "not food" and unreadable replies included, so garbage photos cannot drain the
// shared spend cap for free. A provider failure gives the analysis back. The photo is only forwarded; nothing about it is stored.
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";
import { type Price } from "../_shared/llm/config.ts";
import { costUsd } from "../_shared/llm/pricing.ts";
import { type ChatInput, type LLMProvider, type Usage } from "../_shared/llm/types.ts";
import { type CoachDb } from "../coach-chat/tools/types.ts";
import { type UsageRow } from "../coach-chat/handler.ts";
import { FOOD_PROMPT } from "./prompts.ts";
import { type FoodRequest, foodRequest, modelReply, type ModelReply } from "./schema.ts";

/** Result of taking one analysis from the allowance (`food_consume`). `used` includes this analysis. */
export interface Consumption {
  allowed: boolean;
  reason: "daily" | "rate" | null;
  id?: string;
  tier: "free" | "pro";
  used: number;
  limit: number;
}

export interface FoodService {
  /** Atomically checks and takes one analysis (free 3/day, Pro 60/day, 6/min) and records it in the ledger. */
  consume(userId: string, kind: "photo" | "text", timeZone: string): Promise<Consumption>;
  /** Gives a taken analysis back (the provider failed, so the user got nothing). */
  refund(id: string): Promise<void>;
  spendTodayUsd(): Promise<number>;
  recordUsage(rows: UsageRow[]): Promise<void>;
}

export interface FoodSettings {
  consentVersion: string;
  dailySpendCapUsd: number;
  maxOutputTokens: number;
  timeoutMs: number;
  prices: Record<string, Price>;
  /**
   * Ask for `response_format: json_object`. DeepSeek documents it for text; its vision guide does not say whether it
   * works together with images, so photos default to off (the prompt demands JSON and `extractJson` is tolerant).
   */
  jsonMode: { photo: boolean; text: boolean };
}

export interface FoodDeps {
  verify: TokenVerifier;
  userDb: (token: string) => CoachDb;
  service: FoodService;
  provider: () => LLMProvider;
  settings: FoodSettings;
}

export interface FoodItem {
  name: string;
  grams: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  confidence: number;
}

export interface FoodResult {
  meal_name: string;
  items: FoodItem[];
  totals: { calories: number; protein_g: number; carbs_g: number; fat_g: number; grams: number };
  notes?: string;
}

const round1 = (n: number) => Math.round(n * 10) / 10;

/** Pulls the first JSON object out of the model's text (it may add stray text despite json mode). */
export function extractJson(text: string): unknown {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

/**
 * Validated model reply → result. Calories that disagree with the macros by more than 25 % are replaced by the
 * macro-derived value (4/4/9), so a hallucinated calorie number cannot slip through. Totals are summed here.
 */
export function normalize(reply: ModelReply): FoodResult {
  const items = reply.items.map((item): FoodItem => {
    const derived = 4 * item.protein_g + 4 * item.carbs_g + 9 * item.fat_g;
    const consistent = derived === 0 || item.calories === 0
      ? true
      : Math.abs(item.calories - derived) / Math.max(item.calories, derived) <= 0.25;
    return {
      name: item.name,
      grams: round1(item.grams),
      calories: round1(consistent ? item.calories : derived),
      protein_g: round1(item.protein_g),
      carbs_g: round1(item.carbs_g),
      fat_g: round1(item.fat_g),
      confidence: item.confidence ?? 0.5,
    };
  });
  const sum = (pick: (item: FoodItem) => number) => round1(items.reduce((total, item) => total + pick(item), 0));
  return {
    meal_name: reply.meal_name ?? items[0]?.name ?? "Meal",
    items,
    totals: {
      calories: sum((i) => i.calories),
      protein_g: sum((i) => i.protein_g),
      carbs_g: sum((i) => i.carbs_g),
      fat_g: sum((i) => i.fat_g),
      grams: sum((i) => i.grams),
    },
    ...(reply.notes ? { notes: reply.notes } : {}),
  };
}

function userMessage(input: FoodRequest): ChatInput {
  const header = `locale: ${input.locale}`;
  if (input.kind === "text") {
    return { role: "user", content: `${header}\nDescription:\n<user_data>${input.text.replace(/[<>]/g, " ")}</user_data>` };
  }
  const hint = input.hint ? `\nHint from the user:\n<user_data>${input.hint.replace(/[<>]/g, " ")}</user_data>` : "";
  return {
    role: "user",
    content: [
      { type: "text", text: `${header}${hint}\nEstimate the meal in the photo.` },
      { type: "image_url", image_url: { url: `data:${input.media_type};base64,${input.image_base64}`, detail: "low" } },
    ],
  };
}

const jsonResponse = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });

export function createFoodHandler(deps: FoodDeps) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();
    if (request.method !== "POST") return errorResponse("method_not_allowed", "Use POST.");
    const auth = await requireUser(request, deps.verify);
    if (auth instanceof Response) return auth;

    let raw: unknown;
    try {
      raw = await request.json();
    } catch {
      return errorResponse("invalid_request", "Body must be JSON.");
    }
    const parsed = foodRequest.safeParse(raw);
    if (!parsed.success) {
      return errorResponse("invalid_request", "Invalid request body.",
        parsed.error.issues.map((issue: { path: PropertyKey[]; message: string }) => ({ path: issue.path.map(String).join("."), message: issue.message })));
    }
    const input = parsed.data;
    const { settings, service } = deps;

    try {
      const { data, error } = await deps.userDb(auth.token).rpc("food_has_consent", { p_version: settings.consentVersion });
      if (error) throw new Error(`food_has_consent: ${error.message}`);
      if (data !== true) return errorResponse("consent_required", "Food AI sharing consent is needed.", { required_version: settings.consentVersion });

      if ((await service.spendTodayUsd()) >= settings.dailySpendCapUsd) {
        return errorResponse("food_unavailable", "Food analysis is resting for today. Please try again tomorrow.");
      }
      const taken = await service.consume(auth.userId, input.kind, input.time_zone ?? "UTC");
      if (!taken.allowed) {
        return taken.reason === "rate"
          ? errorResponse("rate_limited", "Too many analyses in a minute. Please wait a moment.")
          : errorResponse("quota_exceeded", "Today's food analyses are used up.", { tier: taken.tier, used: taken.used, limit: taken.limit });
      }

      const provider = deps.provider();
      const started = performance.now();
      let text = "";
      let usage: Usage = { prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0, reasoning_tokens: 0 };
      let status: UsageRow["status"] = "ok";
      try {
        const signal = AbortSignal.timeout(settings.timeoutMs);
        for await (
          const event of provider.streamChat(
            [{ role: "system", content: FOOD_PROMPT }, userMessage(input)],
            [],
            { thinking: false, json: settings.jsonMode[input.kind], maxOutputTokens: settings.maxOutputTokens, signal },
          )
        ) {
          if (event.type === "text") text += event.text;
          if (event.type === "usage") usage = event.usage;
        }
      } catch (error) {
        status = "error";
        console.error("food-analyze model call failed", error instanceof Error ? error.message : error);
      }
      const latency = Math.max(0, Math.round(performance.now() - started));
      await service.recordUsage([{
        user_id: auth.userId, thread_id: null, provider: provider.name, model: provider.model,
        prompt_tokens: usage.prompt_tokens, cached_tokens: usage.cached_tokens, completion_tokens: usage.completion_tokens,
        cost_usd: costUsd(usage, provider.name, provider.model, settings.prices), latency_ms: latency, agent_steps: 1, status,
      }]).catch((error) => console.error("food-analyze usage not stored", error instanceof Error ? error.message : error));
      if (status !== "ok") {
        if (taken.id) await service.refund(taken.id).catch((error) => console.error("food-analyze refund failed", error instanceof Error ? error.message : error));
        return errorResponse("food_unavailable", "The meal could not be analyzed. Please try again.");
      }

      const reply = modelReply.safeParse(extractJson(text));
      if (!reply.success) return errorResponse("food_unavailable", "The meal could not be analyzed. Please try again.");
      if (!reply.data.is_food || reply.data.items.length === 0) {
        return errorResponse("not_food", "No food was found in this " + (input.kind === "photo" ? "photo." : "description."));
      }

      return jsonResponse({ ...normalize(reply.data), remaining: Math.max(0, taken.limit - taken.used), limit: taken.limit });
    } catch (error) {
      console.error("food-analyze failed", error instanceof Error ? error.message : error);
      return errorResponse("internal", "Something went wrong.");
    }
  };
}

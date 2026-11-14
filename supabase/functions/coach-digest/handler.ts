// coach-digest (docs/04-AI-KOC.md §11): a 2-3 sentence comment after a workout, or on the weekly summary. Pro only,
// counted apart from the chat quota, cached per input.
//   1. JWT, input schema                                    → 401 / 400
//   2. current ai_sharing consent                            → 403 consent_required
//   3. global daily spend cap                                → 503 coach_unavailable
//   4. same input before                                     → 200 { cached: true } (no cost, no count)
//   5. Pro + per-kind daily allowance                        → 403 pro_required / 429 quota_exceeded
//   6. one LLM call without tools, thinking off              → 200 { text }
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";
import { type Price } from "../_shared/llm/config.ts";
import { costUsd } from "../_shared/llm/pricing.ts";
import { type LLMProvider, type Usage } from "../_shared/llm/types.ts";
import { type CoachDb } from "../coach-chat/tools/types.ts";
import { type UsageRow } from "../coach-chat/handler.ts";
import { DIGEST_PROMPT_VERSION, WEEKLY_PROMPT, WORKOUT_PROMPT } from "./prompts.ts";
import { digestRequest, type DigestRequest } from "./schema.ts";

export interface Allowance {
  tier: "free" | "pro";
  allowed: boolean;
  reason: "not_pro" | "daily" | null;
  used: number;
  limit: number;
}

export interface StoredDigest {
  body: string;
}

/** Service-role operations (never user data beyond the cached comment). */
export interface DigestService {
  allowance(userId: string, kind: string, timeZone: string): Promise<Allowance>;
  spendTodayUsd(): Promise<number>;
  find(userId: string, kind: string, locale: string, inputHash: string): Promise<StoredDigest | null>;
  save(row: { user_id: string; kind: string; locale: string; input_hash: string; body: string }): Promise<void>;
  recordUsage(rows: UsageRow[]): Promise<void>;
}

export interface DigestSettings {
  consentVersion: string;
  dailySpendCapUsd: number;
  maxOutputTokens: number;
  timeoutMs: number;
  prices: Record<string, Price>;
}

export interface DigestDeps {
  verify: TokenVerifier;
  userDb: (token: string) => CoachDb;
  service: DigestService;
  provider: () => LLMProvider;
  settings: DigestSettings;
}

/** SHA-256 of the prompt version, kind, locale and the canonical input: the same input always maps to one cache row. */
export async function inputHash(request: DigestRequest): Promise<string> {
  const { time_zone: _ignored, ...rest } = request;
  const canonical = JSON.stringify(sortKeys({ v: DIGEST_PROMPT_VERSION, ...rest }));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) => [k, sortKeys(v)]));
  }
  return value;
}

const jsonResponse = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });

/** Keeps the model's text to plain sentences: no markdown or leftovers, at most 600 characters. */
export function cleanComment(text: string): string {
  const plain = text.replace(/[*_#`>]+/g, "").replace(/^\s*[-•]\s+/gm, "").replace(/\s+/g, " ").trim();
  return plain.length <= 600 ? plain : plain.slice(0, plain.lastIndexOf(" ", 600)).trim();
}

export function createDigestHandler(deps: DigestDeps) {
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
    const parsed = digestRequest.safeParse(raw);
    if (!parsed.success) {
      return errorResponse("invalid_request", "Invalid request body.",
        parsed.error.issues.map((issue: { path: PropertyKey[]; message: string }) => ({ path: issue.path.map(String).join("."), message: issue.message })));
    }
    const input = parsed.data;
    const { settings, service } = deps;

    try {
      const { data, error } = await deps.userDb(auth.token).rpc("coach_has_ai_consent", { p_version: settings.consentVersion });
      if (error) throw new Error(`coach_has_ai_consent: ${error.message}`);
      if (data !== true) return errorResponse("consent_required", "AI data sharing consent is needed.", { required_version: settings.consentVersion });

      const hash = await inputHash(input);
      const cached = await service.find(auth.userId, input.kind, input.locale, hash);
      if (cached) return jsonResponse({ text: cached.body, cached: true, kind: input.kind });

      const allowance = await service.allowance(auth.userId, input.kind, input.time_zone ?? "UTC");
      if (!allowance.allowed) {
        return allowance.reason === "not_pro"
          ? errorResponse("pro_required", "Proactive comments are a Pro feature.")
          : errorResponse("quota_exceeded", "Today's comments are used up.", { reason: allowance.reason, used: allowance.used, limit: allowance.limit });
      }
      if ((await service.spendTodayUsd()) >= settings.dailySpendCapUsd) {
        return errorResponse("coach_unavailable", "The coach is resting for today. Please try again tomorrow.");
      }

      const provider = deps.provider();
      const system = input.kind === "workout" ? WORKOUT_PROMPT : WEEKLY_PROMPT;
      const { kind: _kind, locale, time_zone: _tz, ...data2 } = input;
      const user = `locale: ${locale}\nDATA:\n<user_data>${JSON.stringify(data2).replace(/[<>]/g, " ")}</user_data>`;

      const started = performance.now();
      let text = "";
      let usage: Usage = { prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0, reasoning_tokens: 0 };
      let status: UsageRow["status"] = "ok";
      try {
        const signal = AbortSignal.timeout(settings.timeoutMs);
        for await (
          const event of provider.streamChat(
            [{ role: "system", content: system }, { role: "user", content: user }],
            [],
            { thinking: false, maxOutputTokens: settings.maxOutputTokens, signal },
          )
        ) {
          if (event.type === "text") text += event.text;
          if (event.type === "usage") usage = event.usage;
        }
      } catch (error) {
        status = "error";
        console.error("coach-digest model call failed", error instanceof Error ? error.message : error);
      }
      const latency = Math.max(0, Math.round(performance.now() - started));
      await service.recordUsage([{
        user_id: auth.userId, thread_id: null, provider: provider.name, model: provider.model,
        prompt_tokens: usage.prompt_tokens, cached_tokens: usage.cached_tokens, completion_tokens: usage.completion_tokens,
        cost_usd: costUsd(usage, provider.name, provider.model, settings.prices), latency_ms: latency, agent_steps: 1, status,
      }]).catch((error) => console.error("coach-digest usage not stored", error instanceof Error ? error.message : error));

      const comment = cleanComment(text);
      if (status !== "ok" || !comment) return errorResponse("coach_unavailable", "The comment could not be written.");
      await service.save({ user_id: auth.userId, kind: input.kind, locale: input.locale, input_hash: hash, body: comment });
      return jsonResponse({ text: comment, cached: false, kind: input.kind });
    } catch (error) {
      console.error("coach-digest failed", error instanceof Error ? error.message : error);
      return errorResponse("internal", "Something went wrong.");
    }
  };
}

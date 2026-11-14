// coach-chat (docs/04-AI-KOC.md §2):
//   1. JWT, input schema, input hygiene                       → 401 / 400
//   2. current ai_sharing consent                              → 403 consent_required
//   3. global daily spend cap (circuit breaker)                → 503 coach_unavailable
//   4. duplicate of the last answered message                  → 400 duplicate_message
//   5. atomic quota (per minute, per local day, by tier)       → 429 rate_limited / quota_exceeded
//   6. context (system prompt, user summary, last 12 messages)
//   7. agent loop over SSE; then the turn and every LLM call's usage are stored
// User data is read and written with the caller's JWT (RLS). Only quota, spend and usage go through the service role.
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";
import { type Price } from "../_shared/llm/config.ts";
import { costUsd } from "../_shared/llm/pricing.ts";
import { type LLMProvider, type ProviderError } from "../_shared/llm/types.ts";
import { coachChatRequest, looksLikeSpam, sameMessage } from "../_shared/schema.ts";
import { type CoachEvent, sseResponse } from "../_shared/sse.ts";
import { type AgentOutcome, type CallRecord, emptyOutcome, runAgent } from "./agent.ts";
import { buildMessages, buildUserSummary, HISTORY_LIMIT, type HistoryMessage, type UserContext } from "./context.ts";
import { PROPOSAL_TOOLS } from "./tools/propose.ts";
import { READ_TOOLS } from "./tools/read.ts";
import { type CoachDb } from "./tools/types.ts";

export const COACH_TOOLS = [...READ_TOOLS, ...PROPOSAL_TOOLS];

export interface TierLimits {
  daily_messages: number;
  requests_per_minute: number;
  max_agent_steps: number;
  max_output_tokens_turn: number;
  thinking: boolean;
}

export interface QuotaDecision {
  allowed: boolean;
  reason: "rate_minute" | "daily" | null;
  tier: "free" | "pro";
  remaining: number;
  reset_at: string;
  limits: TierLimits;
}

export interface UsageRow {
  user_id: string;
  thread_id: string;
  provider: string;
  model: string;
  prompt_tokens: number;
  cached_tokens: number;
  completion_tokens: number;
  cost_usd: number;
  latency_ms: number;
  agent_steps: number;
  status: "ok" | "error" | "timeout";
}

/** Service-role operations (never user data). */
export interface CoachService {
  consumeQuota(userId: string, timeZone: string): Promise<QuotaDecision>;
  spendTodayUsd(): Promise<number>;
  recordUsage(rows: UsageRow[]): Promise<void>;
}

export interface CoachSettings {
  consentVersion: string;
  dailySpendCapUsd: number;
  turnTimeoutMs: number;
  maxOutputTokensCall: number;
  prices: Record<string, Price>;
}

export interface CoachChatDeps {
  verify: TokenVerifier;
  /** A database handle acting as the caller (their JWT, RLS applies). */
  userDb: (token: string) => CoachDb;
  service: CoachService;
  /** A fresh provider per request; `onSwitch` is told when the primary failed and the fallback takes over. */
  provider: (onSwitch: (error: ProviderError, failed: LLMProvider) => void) => LLMProvider;
  settings: CoachSettings;
  newId?: () => string;
  today?: () => string;
}

const PROGRAM_WORK = /\b(program|routine|rutin|plan|split|antrenman programı)/i;

async function rpc<T>(db: CoachDb, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

export function createCoachChatHandler(deps: CoachChatDeps) {
  const newId = deps.newId ?? (() => crypto.randomUUID());
  const today = deps.today ?? (() => new Date().toISOString().slice(0, 10));

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
    const parsed = coachChatRequest.safeParse(raw);
    if (!parsed.success) {
      const issues = parsed.error.issues.map((issue: { path: PropertyKey[]; message: string }) => ({ path: issue.path.map(String).join("."), message: issue.message }));
      return errorResponse("invalid_request", "Invalid request body.", issues);
    }
    const input = parsed.data;
    if (looksLikeSpam(input.message)) return errorResponse("invalid_request", "The message looks like repeated characters.");

    const userId = auth.userId;
    const db = deps.userDb(auth.token);
    const { settings } = deps;

    try {
      if (!(await rpc<boolean>(db, "coach_has_ai_consent", { p_version: settings.consentVersion }))) {
        return errorResponse("consent_required", "AI data sharing consent is needed.", { required_version: settings.consentVersion });
      }
      if ((await deps.service.spendTodayUsd()) >= settings.dailySpendCapUsd) {
        return errorResponse("coach_unavailable", "The coach is resting for today. Please try again tomorrow.");
      }

      const threadId = input.thread_id ?? newId();
      let history: HistoryMessage[] = [];
      if (input.thread_id) {
        const thread = await rpc<{ messages: HistoryMessage[]; last_user_message: string | null; last_turn_complete: boolean }>(
          db, "coach_thread_history", { p_thread_id: input.thread_id, p_limit: HISTORY_LIMIT },
        );
        if (thread.last_turn_complete && thread.last_user_message && sameMessage(thread.last_user_message, input.message)) {
          return errorResponse("duplicate_message", "This message was just answered.");
        }
        history = thread.messages;
      }

      const quota = await deps.service.consumeQuota(userId, input.time_zone ?? "UTC");
      if (!quota.allowed) {
        const retryAfter = Math.max(1, Math.ceil((Date.parse(quota.reset_at) - Date.now()) / 1000));
        return errorResponse(
          quota.reason === "rate_minute" ? "rate_limited" : "quota_exceeded",
          quota.reason === "rate_minute" ? "Too many requests; wait a moment." : "Daily coach messages used up.",
          { reason: quota.reason, reset_at: quota.reset_at, tier: quota.tier, upgrade_available: quota.tier === "free" },
          { "Retry-After": String(retryAfter) },
        );
      }

      const context = await rpc<UserContext>(db, "coach_user_context", { p_locale: input.locale });
      const messages = buildMessages({
        userSummary: buildUserSummary(context ?? {}, today(), input.locale),
        history,
        message: input.message,
      });
      return sseResponse(streamTurn({ deps, db, userId, threadId, input, messages, quota, context, newId }), CORS_HEADERS);
    } catch (error) {
      console.error("coach-chat failed before streaming", error instanceof Error ? error.message : error);
      return errorResponse("internal", "Something went wrong.");
    }
  };
}

async function* streamTurn(turn: {
  deps: CoachChatDeps;
  db: CoachDb;
  userId: string;
  threadId: string;
  input: { message: string; locale: string };
  messages: ReturnType<typeof buildMessages>;
  quota: QuotaDecision;
  context: UserContext | null;
  newId: () => string;
}): AsyncGenerator<CoachEvent> {
  const { deps, db, threadId, input, quota, newId } = turn;
  const calls: CallRecord[] = [];
  const outcome: AgentOutcome = emptyOutcome();
  let finished = false;
  const provider = deps.provider((error, failed) =>
    calls.push({
      provider: failed.name,
      model: failed.model,
      usage: { prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0, reasoning_tokens: 0 },
      latencyMs: 0,
      step: 0,
      status: error.status === 408 ? "timeout" : "error",
    })
  );

  try {
    yield* runAgent(turn.messages, {
      provider,
      tools: COACH_TOOLS,
      toolContext: { db, locale: input.locale, profile: turn.context?.profile ?? null, newId },
      limits: {
        maxSteps: quota.limits.max_agent_steps,
        maxOutputTokensTurn: quota.limits.max_output_tokens_turn,
        maxOutputTokensCall: deps.settings.maxOutputTokensCall,
        turnTimeoutMs: deps.settings.turnTimeoutMs,
        thinking: quota.limits.thinking && PROGRAM_WORK.test(input.message),
      },
      locale: input.locale,
      onCall: (record) => calls.push(record),
      outcome,
    });
    finished = true;
    yield { type: "usage", ...outcome.usage };
    if (outcome.stopped !== "error") yield { type: "done", thread_id: threadId };
  } finally {
    if (!finished || outcome.status === "partial") {
      outcome.status = "partial";
      const last = outcome.messages.at(-1);
      if (last?.role === "assistant") last.status = "partial";
      else outcome.messages.push({ role: "assistant", content: "", status: "partial" });
    }
    await persist(turn, outcome, calls).catch((error) =>
      console.error("coach-chat could not store the turn", error instanceof Error ? error.message : error)
    );
  }
}

async function persist(
  turn: { deps: CoachChatDeps; db: CoachDb; userId: string; threadId: string; input: { message: string }; newId: () => string },
  outcome: AgentOutcome,
  calls: CallRecord[],
): Promise<void> {
  const { deps, db, userId, threadId, input, newId } = turn;
  const rows = [
    { id: newId(), role: "user", content: input.message, status: "complete" },
    ...outcome.messages.map((message) => ({ id: newId(), ...message, status: message.status ?? "complete" })),
  ];
  const saved = db.rpc("coach_save_turn", { p_thread_id: threadId, p_title: input.message.slice(0, 60), p_messages: rows })
    .then(({ error }) => {
      if (error) throw new Error(`coach_save_turn: ${error.message}`);
    });
  const usage = calls.length
    ? deps.service.recordUsage(calls.map((call) => ({
      user_id: userId,
      thread_id: threadId,
      provider: call.provider,
      model: call.model,
      prompt_tokens: call.usage.prompt_tokens,
      cached_tokens: call.usage.cached_tokens,
      completion_tokens: call.usage.completion_tokens,
      cost_usd: costUsd(call.usage, call.provider, call.model, deps.settings.prices),
      latency_ms: Math.max(0, Math.round(call.latencyMs)),
      agent_steps: call.step,
      status: call.status,
    })))
    : Promise.resolve();
  await Promise.all([saved, usage]);
}

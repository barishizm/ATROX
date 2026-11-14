// publish-score (P087): the client sends its overall Strength Score and weekly workout count; the function checks
// they are plausible and writes them to the user's public profile, only while score sharing is on.
//   1. JWT, input shape                           → 401 / 400
//   2. rate limit (60 publishes per hour)         → 429 rate_limited
//   3. no profile or sharing off                   → 200 { published: false, reason } (nothing is written)
//   4. plausibility                                → 200 { published: false, reason } (previous value stays)
//   5. social_publish                              → 200 { published: true }
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";

export interface PublishFacts {
  has_profile: boolean;
  share_score: boolean;
  last_score: number | null;
  last_provisional: boolean;
  last_at: string | null;
  workouts_7d: number;
  completed_sets: number;
}

export interface PublishService {
  facts(userId: string): Promise<PublishFacts>;
  /** Counts one more publish in the window; false once over the limit. */
  hit(userId: string, action: string, limit: number, windowSeconds: number): Promise<boolean>;
  publish(userId: string, score: number, provisional: boolean, weekly: number): Promise<void>;
}

export interface PublishDeps {
  verify: TokenVerifier;
  service: PublishService;
  now?: () => number;
}

export type PublishReason = "sharing_off" | "no_profile" | "score_jump" | "no_data" | "weekly_mismatch";

/** A published score may move at most this far within a day of the previous publish (unless that one was provisional). */
export const MAX_JUMP = 15;
export const JUMP_WINDOW_MS = 24 * 60 * 60 * 1000;
export const HOURLY_LIMIT = 60;

export interface PublishRequest {
  overall_score: number;
  provisional: boolean;
  weekly_workouts: number;
}

export function parseRequest(raw: unknown): PublishRequest | null {
  if (!raw || typeof raw !== "object") return null;
  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body);
  if (keys.some((key) => !["overall_score", "provisional", "weekly_workouts"].includes(key))) return null;
  const { overall_score: score, provisional, weekly_workouts: weekly } = body;
  if (!Number.isInteger(score) || (score as number) < 1 || (score as number) > 99) return null;
  if (typeof provisional !== "boolean") return null;
  if (!Number.isInteger(weekly) || (weekly as number) < 0 || (weekly as number) > 50) return null;
  return { overall_score: score as number, provisional, weekly_workouts: weekly as number };
}

/** The sanity rules: null means the values are plausible. */
export function check(request: PublishRequest, facts: PublishFacts, nowMs: number): PublishReason | null {
  // A score needs some synced training behind it; a brand-new account cannot publish a 90.
  if (facts.completed_sets < 3) return "no_data";
  // Weekly count should roughly match the workouts the server has already received (sync may lag by one or two).
  if (request.weekly_workouts > facts.workouts_7d + 2) return "weekly_mismatch";
  if (facts.last_score !== null && facts.last_at && !facts.last_provisional) {
    const age = nowMs - Date.parse(facts.last_at);
    if (age < JUMP_WINDOW_MS && Math.abs(request.overall_score - facts.last_score) > MAX_JUMP) return "score_jump";
  }
  return null;
}

const json = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });

export function createPublishHandler(deps: PublishDeps) {
  const now = deps.now ?? Date.now;
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
    const body = parseRequest(raw);
    if (!body) return errorResponse("invalid_request", "overall_score 1-99, provisional, weekly_workouts 0-50 are required.");

    try {
      if (!(await deps.service.hit(auth.userId, "publish_score", HOURLY_LIMIT, 3600))) {
        return errorResponse("rate_limited", "Too many publishes. Try again later.");
      }
      const facts = await deps.service.facts(auth.userId);
      if (!facts.has_profile) return json({ published: false, reason: "no_profile" satisfies PublishReason });
      // Sharing off: nothing is written, the stored score stays empty.
      if (!facts.share_score) return json({ published: false, reason: "sharing_off" satisfies PublishReason });
      const reason = check(body, facts, now());
      if (reason) return json({ published: false, reason });
      await deps.service.publish(auth.userId, body.overall_score, body.provisional, body.weekly_workouts);
      return json({ published: true });
    } catch (error) {
      console.error("publish-score failed", error instanceof Error ? error.message : error);
      return errorResponse("internal", "Could not publish the score.");
    }
  };
}

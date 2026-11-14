// contribute (P093, docs/02-MIMARI.md §3.3): the device sends a monthly, already-banded summary under a random
// `contribution_key`. The JWT is used ONLY for rate limiting; the user id goes to `hit` and nowhere else: not into the
// table, not into a log line. Everything written is validated against physiological limits.
//   POST   { contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band, frequency_band, month,
//            model_version, lifts: [{ exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month }] }  → 200 { stored }
//   DELETE { contribution_key }                                                                          → 200 { deleted }
import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse } from "../_shared/errors.ts";

export interface ContributionRow {
  contribution_key: string;
  sex: "male" | "female";
  age_band: number;
  bodyweight_kg: number;
  height_band: number;
  experience_band: string;
  frequency_band: string;
  month: string;
  exercise_id: string;
  best_e1rm_kg: number;
  best_set_reps: number;
  sessions_in_month: number;
  model_version: string;
}

export interface ContributionStore {
  /** Upserts on (contribution_key, month, exercise_id). */
  upsert(rows: ContributionRow[]): Promise<void>;
  /** Removes every row of the key; returns how many. */
  remove(contributionKey: string): Promise<number>;
}

export interface ContributeDeps {
  verify: TokenVerifier;
  /** Counts one more call for this caller in the window; false once over the limit. The id never leaves this call. */
  hit(userId: string, action: string, limit: number, windowSeconds: number): Promise<boolean>;
  store: ContributionStore;
  now?: () => number;
}

export const EXPERIENCE_BANDS = ["none", "under_6_months", "six_months_to_2_years", "two_to_5_years", "over_5_years"];
export const FREQUENCY_BANDS = ["1-2", "3-4", "5-6", "7+"];
export const MAX_LIFTS = 40;
export const HOURLY_LIMIT = 20;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const EXERCISE_ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;
const MONTH = /^(20\d\d)-(0[1-9]|1[0-2])$/;

const isInt = (value: unknown, min: number, max: number): value is number =>
  Number.isInteger(value) && (value as number) >= min && (value as number) <= max;

export function parseKey(raw: unknown): string | null {
  if (!raw || typeof raw !== "object") return null;
  const body = raw as Record<string, unknown>;
  if (Object.keys(body).some((key) => key !== "contribution_key")) return null;
  const key = body.contribution_key;
  return typeof key === "string" && UUID.test(key) ? key : null;
}

/** Validates the payload and flattens it to table rows; null when anything is out of bounds. */
export function parseContribution(raw: unknown, nowMs: number): ContributionRow[] | null {
  if (!raw || typeof raw !== "object") return null;
  const b = raw as Record<string, unknown>;
  const allowed = [
    "contribution_key", "sex", "age_band", "bodyweight_kg", "height_band", "experience_band", "frequency_band", "month",
    "model_version", "lifts",
  ];
  if (Object.keys(b).some((key) => !allowed.includes(key))) return null;
  if (typeof b.contribution_key !== "string" || !UUID.test(b.contribution_key)) return null;
  if (b.sex !== "male" && b.sex !== "female") return null;
  if (!isInt(b.age_band, 10, 95) || b.age_band % 5 !== 0) return null;
  if (!isInt(b.bodyweight_kg, 30, 300)) return null;
  if (!isInt(b.height_band, 120, 230) || b.height_band % 5 !== 0) return null;
  if (typeof b.experience_band !== "string" || !EXPERIENCE_BANDS.includes(b.experience_band)) return null;
  if (typeof b.frequency_band !== "string" || !FREQUENCY_BANDS.includes(b.frequency_band)) return null;
  if (typeof b.model_version !== "string" || b.model_version.length < 1 || b.model_version.length > 64) return null;
  const month = typeof b.month === "string" ? MONTH.exec(b.month) : null;
  if (!month) return null;
  // Only a month that has ended, and not older than two years.
  const monthStart = Date.UTC(Number(month[1]), Number(month[2]) - 1, 1);
  const now = new Date(nowMs);
  const currentMonthStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  if (monthStart >= currentMonthStart || currentMonthStart - monthStart > 800 * 86_400_000) return null;
  if (!Array.isArray(b.lifts) || b.lifts.length < 1 || b.lifts.length > MAX_LIFTS) return null;

  const seen = new Set<string>();
  const rows: ContributionRow[] = [];
  for (const item of b.lifts) {
    if (!item || typeof item !== "object") return null;
    const lift = item as Record<string, unknown>;
    if (Object.keys(lift).some((key) => !["exercise_id", "best_e1rm_kg", "best_set_reps", "sessions_in_month"].includes(key))) return null;
    if (typeof lift.exercise_id !== "string" || !EXERCISE_ID.test(lift.exercise_id) || seen.has(lift.exercise_id)) return null;
    seen.add(lift.exercise_id);
    const e1rm = lift.best_e1rm_kg;
    if (typeof e1rm !== "number" || !Number.isFinite(e1rm) || e1rm <= 0 || e1rm > 700) return null;
    if (!isInt(lift.best_set_reps, 1, 30)) return null;
    if (!isInt(lift.sessions_in_month, 1, 62)) return null;
    rows.push({
      contribution_key: b.contribution_key, sex: b.sex, age_band: b.age_band, bodyweight_kg: b.bodyweight_kg,
      height_band: b.height_band, experience_band: b.experience_band, frequency_band: b.frequency_band,
      month: b.month as string, exercise_id: lift.exercise_id, best_e1rm_kg: Math.round(e1rm * 10) / 10,
      best_set_reps: lift.best_set_reps, sessions_in_month: lift.sessions_in_month, model_version: b.model_version,
    });
  }
  return rows;
}

const json = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });

export function createContributeHandler(deps: ContributeDeps) {
  const now = deps.now ?? Date.now;
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...CORS_HEADERS, "Access-Control-Allow-Methods": "POST, DELETE, OPTIONS" } });
    if (request.method !== "POST" && request.method !== "DELETE") return errorResponse("method_not_allowed", "Use POST or DELETE.");
    const auth = await requireUser(request, deps.verify);
    if (auth instanceof Response) return auth;

    let raw: unknown;
    try {
      raw = await request.json();
    } catch {
      return errorResponse("invalid_request", "Body must be JSON.");
    }

    try {
      if (!(await deps.hit(auth.userId, request.method === "POST" ? "contribute" : "contribute_delete", HOURLY_LIMIT, 3600))) {
        return errorResponse("rate_limited", "Too many requests. Try again later.");
      }
      if (request.method === "DELETE") {
        const key = parseKey(raw);
        if (!key) return errorResponse("invalid_request", "contribution_key must be a UUID.");
        return json({ deleted: await deps.store.remove(key) });
      }
      const rows = parseContribution(raw, now());
      if (!rows) return errorResponse("invalid_request", "The summary is malformed or outside plausible limits.");
      await deps.store.upsert(rows);
      return json({ stored: rows.length });
    } catch (error) {
      // Never log the caller or the payload; the message alone is enough to find the failing call.
      console.error("contribute failed", error instanceof Error ? error.message : "unknown");
      return errorResponse("internal", "Could not store the contribution.");
    }
  };
}

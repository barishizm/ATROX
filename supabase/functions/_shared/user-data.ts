// Shared by export-data and delete-account (P045).

/** The user's own tables, parents before children (docs/02-MIMARI.md §3.1). Delete walks it backwards. */
export const USER_TABLES = [
  "profiles",
  "user_settings",
  "consents",
  "body_measurements",
  "custom_exercises",
  "routines",
  "routine_days",
  "routine_exercises",
  "workouts",
  "workout_exercises",
  "sets",
  "personal_records",
  "score_snapshots",
  "insights",
  "entitlements",
  "coach_threads",
  "coach_messages",
  "coach_memory",
  "coach_usage",
  "coach_digests",
  "food_entries",
  "nutrition_targets",
  "diary_logs",
  "food_analyses",
  // Friendships, requests, blocks and reports reference auth.users with ON DELETE CASCADE, so deleting the auth user
  // removes them; they hold other people's data too and are not part of the export.
  "public_profiles",
] as const;

export type UserTable = (typeof USER_TABLES)[number];
export type Row = Record<string, unknown>;

/** What the handlers need from Supabase; `index.ts` implements it with supabase-js, tests with a fake. */
export interface UserDataStore {
  /** The user id behind a JWT, or null when the token is invalid or expired. */
  userIdFromToken(jwt: string): Promise<string | null>;
  /** Every row of `table` owned by `userId`, tombstones included. */
  rows(table: UserTable, userId: string): Promise<Row[]>;
  deleteRows(table: UserTable, userId: string): Promise<void>;
  deleteAuthUser(userId: string): Promise<void>;
  /** Counts one more call for this user in the window; false once over the limit. */
  hit?(userId: string, action: string, limit: number, windowSeconds: number): Promise<boolean>;
  /** Epoch seconds of the user's last interactive sign-in (the newest `amr` timestamp), or null when unknown. */
  signedInAt?(jwt: string): number | null;
}

export interface GuardOptions {
  action: string;
  limit: number;
  windowSeconds: number;
  /** Reject (401 reauth_required) tokens whose last sign-in is older than this; undefined = no requirement. */
  maxSignInAgeSeconds?: number;
  now?: () => number;
}

/** Newest `amr[].timestamp` of an already verified Supabase access token. A refresh keeps `amr`, unlike `iat`. */
export function signInTimeFromJwt(jwt: string): number | null {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(part.padEnd(Math.ceil(part.length / 4) * 4, "=")));
    const stamps = (Array.isArray(claims.amr) ? claims.amr : [])
      .map((entry: { timestamp?: unknown }) => entry?.timestamp)
      .filter((t: unknown): t is number => typeof t === "number" && Number.isFinite(t));
    return stamps.length ? Math.max(...stamps) : null;
  } catch {
    return null;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/** The bearer token of the request, or null. */
export function bearer(request: Request): string | null {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  return match ? match[1] : null;
}

/** Common gate: POST only, a valid user token. Returns the user id or the error response. */
export async function authenticate(
  request: Request,
  store: UserDataStore,
  guard?: GuardOptions,
): Promise<string | Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const token = bearer(request);
  if (!token) return json({ error: "unauthorized" }, 401);
  const userId = await store.userIdFromToken(token);
  if (!userId) return json({ error: "unauthorized" }, 401);
  if (guard?.maxSignInAgeSeconds !== undefined) {
    const at = store.signedInAt?.(token) ?? null;
    const nowSeconds = (guard.now ?? Date.now)() / 1000;
    // Unknown sign-in time counts as stale: the app must sign in again rather than skip the check.
    if (at === null || nowSeconds - at > guard.maxSignInAgeSeconds) return json({ error: "reauth_required" }, 401);
  }
  if (guard && store.hit && !(await store.hit(userId, guard.action, guard.limit, guard.windowSeconds))) {
    return json({ error: "rate_limited" }, 429);
  }
  return userId;
}

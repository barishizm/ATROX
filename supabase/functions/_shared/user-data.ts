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
export async function authenticate(request: Request, store: UserDataStore): Promise<string | Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const token = bearer(request);
  if (!token) return json({ error: "unauthorized" }, 401);
  const userId = await store.userIdFromToken(token);
  if (!userId) return json({ error: "unauthorized" }, 401);
  return userId;
}

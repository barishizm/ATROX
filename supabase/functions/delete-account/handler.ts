import { authenticate, json, USER_TABLES, type UserDataStore } from "../_shared/user-data.ts";

export interface DeleteDeps {
  store: UserDataStore;
  /** Revokes the user's Sign in with Apple tokens; nil when Apple is not configured. */
  revokeApple?: (authorizationCode: string) => Promise<void>;
}

/**
 * delete-account (P045): revoke Apple tokens (when the app sends a fresh authorization code), delete every row of
 * the user — children first — and finally the Auth user. Body: `{ "apple_authorization_code"?: string }`.
 * A failed Apple revocation does not keep the account alive; it is reported as `apple_revoked: false`.
 */
export function createDeleteHandler({ store, revokeApple }: DeleteDeps) {
  return async (request: Request): Promise<Response> => {
    const userId = await authenticate(request, store);
    if (userId instanceof Response) return userId;

    let code: string | undefined;
    const text = await request.text();
    if (text.trim()) {
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        return json({ error: "invalid_body" }, 400);
      }
      const value = (body as Record<string, unknown> | null)?.apple_authorization_code;
      if (value !== undefined && (typeof value !== "string" || value.length === 0 || value.length > 2048)) {
        return json({ error: "invalid_body" }, 400);
      }
      code = value as string | undefined;
    }

    let appleRevoked: boolean | null = null;
    if (code && revokeApple) {
      try {
        await revokeApple(code);
        appleRevoked = true;
      } catch (error) {
        console.error("apple revoke failed", error instanceof Error ? error.message : error);
        appleRevoked = false;
      }
    }

    try {
      for (const table of [...USER_TABLES].reverse()) await store.deleteRows(table, userId);
      await store.deleteAuthUser(userId);
    } catch (error) {
      console.error("delete-account failed", error instanceof Error ? error.message : error);
      return json({ error: "delete_failed" }, 500);
    }
    return json({ deleted: true, apple_revoked: appleRevoked });
  };
}

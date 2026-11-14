import { errorResponse } from "./errors.ts";

/** Resolves a JWT to a user id, or null when it is invalid or expired. */
export type TokenVerifier = (jwt: string) => Promise<string | null>;

export function bearerToken(request: Request): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("Authorization") ?? "");
  return match ? match[1] : null;
}

/** The caller's user id, or the 401 response. */
export async function requireUser(
  request: Request,
  verify: TokenVerifier,
): Promise<{ userId: string; token: string } | Response> {
  const token = bearerToken(request);
  if (!token) return errorResponse("unauthorized", "Missing bearer token.");
  const userId = await verify(token);
  if (!userId) return errorResponse("unauthorized", "Invalid or expired token.");
  return { userId, token };
}

// Structured errors and CORS for the coach functions (P072). Error bodies: { error: { code, message } }.

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

export type ErrorCode =
  | "unauthorized"
  | "invalid_request"
  | "method_not_allowed"
  | "consent_required"
  | "rate_limited"
  | "quota_exceeded"
  | "duplicate_message"
  | "coach_unavailable"
  | "internal";

const STATUS: Record<ErrorCode, number> = {
  unauthorized: 401,
  invalid_request: 400,
  method_not_allowed: 405,
  consent_required: 403,
  rate_limited: 429,
  quota_exceeded: 429,
  duplicate_message: 400,
  coach_unavailable: 503,
  internal: 500,
};

export function errorResponse(
  code: ErrorCode,
  message: string,
  details?: unknown,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ error: { code, message, ...(details === undefined ? {} : { details }) } }), {
    status: STATUS[code],
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

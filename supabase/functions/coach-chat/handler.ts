import { requireUser, type TokenVerifier } from "../_shared/auth.ts";
import { CORS_HEADERS, errorResponse, preflight } from "../_shared/errors.ts";
import { coachChatRequest, type CoachChatRequest } from "../_shared/schema.ts";
import { type CoachEvent, sseResponse } from "../_shared/sse.ts";

/** Streams the model's answer as events (text, usage, ...). P073 replaces the fake with the provider layer. */
export type CoachLLM = (request: CoachChatRequest & { userId: string }) => AsyncIterable<CoachEvent>;

export interface CoachChatDeps {
  verify: TokenVerifier;
  llm: CoachLLM;
  newThreadId?: () => string;
}

/** coach-chat (P072): JWT → input schema → SSE stream. Consent, quota, context and the agent loop come in P073–P076. */
export function createCoachChatHandler({ verify, llm, newThreadId = () => crypto.randomUUID() }: CoachChatDeps) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();
    if (request.method !== "POST") return errorResponse("method_not_allowed", "Use POST.");

    const auth = await requireUser(request, verify);
    if (auth instanceof Response) return auth;

    let raw: unknown;
    try {
      raw = await request.json();
    } catch {
      return errorResponse("invalid_request", "Body must be JSON.");
    }
    const parsed = coachChatRequest.safeParse(raw);
    if (!parsed.success) {
      const issues = parsed.error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message }));
      return errorResponse("invalid_request", "Invalid request body.", issues);
    }

    const input = parsed.data;
    const userId = auth.userId;
    const threadId = input.thread_id ?? newThreadId();
    async function* events(): AsyncGenerator<CoachEvent> {
      yield* llm({ ...input, userId });
      yield { type: "done", thread_id: threadId };
    }
    return sseResponse(events(), CORS_HEADERS);
  };
}

/** Placeholder model until P073: a fixed answer, streamed in small pieces. */
export async function* fakeLLM(request: CoachChatRequest): AsyncGenerator<CoachEvent> {
  const answer = request.locale.startsWith("tr")
    ? "Merhaba! Ben ATROX koçuyum. Henüz yer tutucu bir yanıt veriyorum."
    : "Hi! I'm the ATROX coach. This is a placeholder answer for now.";
  for (const text of answer.match(/\S+\s*/g) ?? []) yield { type: "text_delta", text };
  yield { type: "usage", prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0 };
}

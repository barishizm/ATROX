// Server-sent events for the coach (docs/04-AI-KOC.md §2). Frame: `event: <type>\ndata: <json>\n\n`.

export type CoachEvent =
  | { type: "text_delta"; text: string }
  | { type: "tool_activity"; name: string; status: "started" | "finished" }
  | { type: "proposal"; proposal: Record<string, unknown> }
  | { type: "quota"; remaining: number; daily_messages: number; reset_at: string; tier: "free" | "pro" }
  | { type: "usage"; prompt_tokens: number; cached_tokens: number; completion_tokens: number }
  | { type: "error"; code: string; message: string }
  | { type: "done"; thread_id: string };

export const EVENT_TYPES = ["text_delta", "tool_activity", "proposal", "quota", "usage", "error", "done"] as const;

export function encodeEvent(event: CoachEvent): string {
  const { type, ...data } = event;
  return `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
}

export const SSE_HEADERS: Record<string, string> = {
  "Content-Type": "text/event-stream; charset=utf-8",
  "Cache-Control": "no-cache, no-transform",
  "Connection": "keep-alive",
  "X-Accel-Buffering": "no",
};

/** A streaming Response from an event producer. An exception becomes one `error` event; the stream then closes. */
export function sseResponse(events: AsyncIterable<CoachEvent>, headers: Record<string, string> = {}): Response {
  const encoder = new TextEncoder();
  const iterator = events[Symbol.asyncIterator]();
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const next = await iterator.next();
        if (cancelled) return;
        if (next.done) controller.close();
        else controller.enqueue(encoder.encode(encodeEvent(next.value)));
      } catch (error) {
        if (cancelled) return;
        console.error("coach stream failed", error instanceof Error ? error.message : error);
        controller.enqueue(encoder.encode(encodeEvent({ type: "error", code: "internal", message: "Stream failed." })));
        controller.close();
      }
    },
    async cancel() {
      // The client went away: stop the producer (its `finally` blocks still run, e.g. to store a partial turn).
      cancelled = true;
      await iterator.return?.();
    },
  });
  return new Response(body, { status: 200, headers: { ...SSE_HEADERS, ...headers } });
}

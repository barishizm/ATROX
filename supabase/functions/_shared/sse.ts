// Server-sent events for the coach (docs/04-AI-KOC.md §2). Frame: `event: <type>\ndata: <json>\n\n`.

export type CoachEvent =
  | { type: "text_delta"; text: string }
  | { type: "tool_activity"; name: string; status: "started" | "finished" }
  | { type: "proposal"; proposal: Record<string, unknown> }
  | { type: "usage"; prompt_tokens: number; cached_tokens: number; completion_tokens: number }
  | { type: "error"; code: string; message: string }
  | { type: "done"; thread_id: string };

export const EVENT_TYPES = ["text_delta", "tool_activity", "proposal", "usage", "error", "done"] as const;

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
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const next = await iterator.next();
        if (next.done) controller.close();
        else controller.enqueue(encoder.encode(encodeEvent(next.value)));
      } catch (error) {
        console.error("coach stream failed", error instanceof Error ? error.message : error);
        controller.enqueue(encoder.encode(encodeEvent({ type: "error", code: "internal", message: "Stream failed." })));
        controller.close();
      }
    },
    async cancel() {
      await iterator.return?.();
    },
  });
  return new Response(body, { status: 200, headers: { ...SSE_HEADERS, ...headers } });
}

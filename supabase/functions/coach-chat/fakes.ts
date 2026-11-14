// Test doubles for coach-chat: a scripted LLM and an RPC fake that behaves like the RLS-scoped SQL functions.
import { type ChatMessage, type LLMEvent, type LLMProvider, ProviderError, type ToolDefinition } from "../_shared/llm/types.ts";
import { type CoachDb, type DbError } from "./tools/types.ts";

/** Each step is the list of events the model streams for one call (or an error to throw). */
export type Script = (LLMEvent[] | Error)[];

export class ScriptedLLM implements LLMProvider {
  readonly name = "fake" as const;
  readonly model = "scripted";
  calls: { messages: ChatMessage[]; tools: ToolDefinition[]; maxOutputTokens: number; thinking: boolean }[] = [];
  constructor(private readonly script: Script, private readonly delayMs = 0) {}

  async *streamChat(messages: ChatMessage[], tools: ToolDefinition[], options: { thinking: boolean; maxOutputTokens: number; signal?: AbortSignal }) {
    this.calls.push({ messages: structuredClone(messages), tools, maxOutputTokens: options.maxOutputTokens, thinking: options.thinking });
    const step = this.script[this.calls.length - 1] ?? [{ type: "text", text: "…" }, { type: "finish", reason: "stop" }];
    if (this.delayMs) {
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, this.delayMs);
        options.signal?.addEventListener("abort", () => {
          clearTimeout(timer);
          reject(new DOMException("aborted", "AbortError"));
        });
      });
    }
    if (step instanceof Error) throw step;
    for (const event of step) {
      if (event.type === "finish" && event.reason === "__throw__") throw new ProviderError("mid-stream", false);
      yield event;
    }
  }
}

export const usage = (completion = 10, prompt = 100, cached = 0): LLMEvent => ({
  type: "usage",
  usage: { prompt_tokens: prompt, cached_tokens: cached, completion_tokens: completion, reasoning_tokens: 0 },
});

export function toolCall(name: string, args: unknown, id = `call_${name}`): LLMEvent {
  return { type: "tool_call", call: { id, type: "function", function: { name, arguments: JSON.stringify(args) } } };
}

export function say(text: string, completion = 10): LLMEvent[] {
  return [{ type: "text", text }, usage(completion), { type: "finish", reason: "stop" }];
}

type Handler = (args: Record<string, unknown>) => unknown;

/** Records every call; unknown functions answer null. A handler may throw `{ message }` to simulate a DB error. */
export class FakeDb implements CoachDb {
  calls: { fn: string; args: Record<string, unknown> }[] = [];
  constructor(public handlers: Record<string, Handler> = {}) {}

  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: DbError | null }> {
    this.calls.push({ fn, args });
    try {
      const handler = this.handlers[fn];
      return Promise.resolve({ data: handler ? handler(args) : null, error: null });
    } catch (error) {
      return Promise.resolve({ data: null, error: { message: (error as { message?: string }).message ?? String(error) } });
    }
  }

  called(fn: string) {
    return this.calls.filter((call) => call.fn === fn);
  }
}

export const CATALOG: Record<string, { id: string; name: string; equipment: string | null; movement_pattern: string; custom: boolean }> = {
  "goblet-squat": { id: "goblet-squat", name: "Goblet Squat", equipment: "dumbbell", movement_pattern: "squat", custom: false },
  "dumbbell-bench-press": { id: "dumbbell-bench-press", name: "Dumbbell Bench Press", equipment: "dumbbell", movement_pattern: "horizontal_push", custom: false },
  "barbell-bench-press": { id: "barbell-bench-press", name: "Barbell Bench Press", equipment: "barbell", movement_pattern: "horizontal_push", custom: false },
  "push-up": { id: "push-up", name: "Push-Up", equipment: "body_only", movement_pattern: "horizontal_push", custom: false },
};

export function lookup(args: Record<string, unknown>) {
  return (args.p_ids as string[]).filter((id) => id in CATALOG).map((id) => CATALOG[id]);
}

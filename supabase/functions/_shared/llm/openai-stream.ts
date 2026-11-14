// Parses an OpenAI-compatible streaming response (`data: {chunk}\n\n` … `data: [DONE]`) into LLM events.
// Tool calls arrive in pieces keyed by `index`: the first piece carries id + name, later ones append to
// `function.arguments`. They are emitted whole, once the stream finishes.
import { type LLMEvent, ProviderError, type ToolCall, type Usage } from "./types.ts";

interface Chunk {
  choices?: {
    delta?: {
      content?: string | null;
      tool_calls?: { index: number; id?: string; type?: string; function?: { name?: string; arguments?: string } }[];
    };
    finish_reason?: string | null;
  }[];
  usage?: RawUsage | null;
  error?: { message?: string; code?: number | string };
}

interface RawUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: { cached_tokens?: number } | null;
  completion_tokens_details?: { reasoning_tokens?: number } | null;
  prompt_cache_hit_tokens?: number;
}

export function parseUsage(raw: RawUsage): Usage {
  const cached = raw.prompt_tokens_details?.cached_tokens ?? raw.prompt_cache_hit_tokens ?? 0;
  return {
    prompt_tokens: raw.prompt_tokens ?? 0,
    cached_tokens: cached,
    completion_tokens: raw.completion_tokens ?? 0,
    reasoning_tokens: raw.completion_tokens_details?.reasoning_tokens ?? 0,
  };
}

/** Lines of a byte stream, split on \n (a trailing \r is dropped). */
async function* lines(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const bytes of body) {
    buffer += decoder.decode(bytes, { stream: true });
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      yield buffer.slice(0, newline).replace(/\r$/, "");
      buffer = buffer.slice(newline + 1);
    }
  }
  buffer += decoder.decode();
  if (buffer) yield buffer.replace(/\r$/, "");
}

export async function* parseChatStream(body: ReadableStream<Uint8Array>): AsyncGenerator<LLMEvent> {
  const calls = new Map<number, ToolCall>();
  let finish = "stop";
  let usage: Usage | undefined;

  for await (const line of lines(body)) {
    if (!line.startsWith("data:")) continue; // keep-alive comments, event names, blank lines
    const data = line.slice(5).trim();
    if (data === "[DONE]") break;
    let chunk: Chunk;
    try {
      chunk = JSON.parse(data);
    } catch {
      continue;
    }
    if (chunk.error) throw new ProviderError(chunk.error.message ?? "stream error", false);
    if (chunk.usage) usage = parseUsage(chunk.usage);
    for (const choice of chunk.choices ?? []) {
      const delta = choice.delta;
      if (delta?.content) yield { type: "text", text: delta.content };
      for (const piece of delta?.tool_calls ?? []) {
        const call = calls.get(piece.index) ??
          { id: "", type: "function" as const, function: { name: "", arguments: "" } };
        if (piece.id) call.id = piece.id;
        if (piece.function?.name) call.function.name += piece.function.name;
        if (piece.function?.arguments) call.function.arguments += piece.function.arguments;
        calls.set(piece.index, call);
      }
      if (choice.finish_reason) finish = choice.finish_reason;
    }
  }

  for (const [index, call] of [...calls.entries()].sort(([a], [b]) => a - b)) {
    yield { type: "tool_call", call: { ...call, id: call.id || `call_${index}` } };
  }
  if (usage) yield { type: "usage", usage };
  yield { type: "finish", reason: finish };
}

import { assert, assertEquals } from "../testing.ts";
import { DEFAULT_PRICES, loadLLMConfig } from "./config.ts";
import { parseChatStream } from "./openai-stream.ts";
import { costUsd } from "./pricing.ts";
import { deepSeekProvider, type Fetch, withRetry } from "./providers.ts";
import { type LLMEvent, ProviderError } from "./types.ts";

function streamOf(text: string, pieceSize = 7): ReadableStream<Uint8Array> {
  const bytes = new TextEncoder().encode(text);
  let offset = 0;
  return new ReadableStream({
    pull(controller) {
      if (offset >= bytes.length) return controller.close();
      controller.enqueue(bytes.slice(offset, offset + pieceSize));
      offset += pieceSize;
    },
  });
}

function sse(chunks: unknown[]): string {
  return ": keep-alive\n\n" + chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") +
    "data: [DONE]\n\n";
}

async function collect(events: AsyncIterable<LLMEvent>): Promise<LLMEvent[]> {
  const all: LLMEvent[] = [];
  for await (const event of events) all.push(event);
  return all;
}

const TEXT_STREAM = sse([
  { choices: [{ delta: { role: "assistant", content: "Mer" } }] },
  { choices: [{ delta: { content: "haba" } }] },
  { choices: [{ delta: {}, finish_reason: "stop" }] },
  {
    choices: [],
    usage: {
      prompt_tokens: 3000,
      completion_tokens: 400,
      prompt_tokens_details: { cached_tokens: 2500 },
      completion_tokens_details: { reasoning_tokens: 0 },
    },
  },
]);

Deno.test("stream parser: text pieces, usage and finish, across arbitrary byte boundaries", async () => {
  const events = await collect(parseChatStream(streamOf(TEXT_STREAM, 5)));
  const text = events.filter((event) => event.type === "text").map((event) => event.type === "text" ? event.text : "");
  assertEquals(text, ["Mer", "haba"]);
  assertEquals(events.at(-2), {
    type: "usage",
    usage: { prompt_tokens: 3000, cached_tokens: 2500, completion_tokens: 400, reasoning_tokens: 0 },
  });
  assertEquals(events.at(-1), { type: "finish", reason: "stop" });
});

Deno.test("stream parser: tool calls split over chunks are joined by index", async () => {
  const body = sse([
    { choices: [{ delta: { tool_calls: [{ index: 0, id: "call_a", type: "function", function: { name: "get_scores", arguments: "" } }] } }] },
    { choices: [{ delta: { tool_calls: [{ index: 1, id: "call_b", type: "function", function: { name: "get_routine", arguments: "{}" } }] } }] },
    { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: "{\"sco" } }] } }] },
    { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: "pe\":\"muscle\"}" } }] } }] },
    { choices: [{ delta: {}, finish_reason: "tool_calls" }], usage: { prompt_tokens: 10, completion_tokens: 5, prompt_cache_hit_tokens: 4 } },
  ]);
  const events = await collect(parseChatStream(streamOf(body, 11)));
  const calls = events.flatMap((event) => event.type === "tool_call" ? [event.call] : []);
  assertEquals(calls, [
    { id: "call_a", type: "function", function: { name: "get_scores", arguments: "{\"scope\":\"muscle\"}" } },
    { id: "call_b", type: "function", function: { name: "get_routine", arguments: "{}" } },
  ]);
  const usage = events.find((event) => event.type === "usage");
  assertEquals(usage?.type === "usage" && usage.usage.cached_tokens, 4, "DeepSeek's prompt_cache_hit_tokens is read");
  assertEquals(events.at(-1), { type: "finish", reason: "tool_calls" });
});

Deno.test("stream parser: an error chunk mid-stream throws", async () => {
  const body = sse([{ choices: [{ delta: { content: "a" } }] }, { error: { message: "upstream died", code: 502 } }]);
  let thrown: unknown;
  try {
    await collect(parseChatStream(streamOf(body)));
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderError);
});

function recordingFetch(responses: (() => Response)[], seen: { url: string; body: Record<string, unknown> }[]): Fetch {
  let call = 0;
  return (url, init) => {
    seen.push({ url, body: JSON.parse(init.body as string) });
    const next = responses[call++];
    return next ? Promise.resolve(next()) : Promise.reject(new TypeError("no more responses"));
  };
}

const ok = () => new Response(streamOf(TEXT_STREAM), { status: 200, headers: { "Content-Type": "text/event-stream" } });

Deno.test("DeepSeek request: thinking enabled/disabled object", async () => {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const provider = deepSeekProvider({ apiKey: "k", model: "deepseek-flash", baseUrl: "https://ds.test", timeoutMs: 1000, fetch: recordingFetch([ok], seen) });
  await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
  assertEquals(seen[0].url, "https://ds.test/chat/completions");
  assertEquals(seen[0].body.thinking, { type: "disabled" });
  assertEquals("provider" in seen[0].body, false);
});

function retrying(responses: (() => Response)[], apiKey: string | undefined = "k") {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const retries: number[] = [];
  const provider = withRetry(
    deepSeekProvider({ apiKey, model: "deepseek-flash", baseUrl: "https://ds.test", timeoutMs: 1000, fetch: recordingFetch(responses, seen) }),
    (error) => retries.push(error.status ?? 0),
  );
  return { seen, retries, provider };
}

const hi = [{ role: "user" as const, content: "hi" }];
const options = { thinking: false, maxOutputTokens: 100 };

Deno.test("retry: 5xx, 429 and network errors are retried once", async () => {
  for (const failure of [() => new Response("x", { status: 503 }), () => new Response("x", { status: 429 })]) {
    const { seen, retries, provider } = retrying([failure, ok]);
    const events = await collect(provider.streamChat(hi, [], options));
    assertEquals(seen.length, 2);
    assertEquals(retries.length, 1);
    assert(events.some((event) => event.type === "text"));
  }
  const network = retrying([]); // every fetch rejects: one retry, then the error surfaces
  let thrown: unknown;
  try {
    await collect(network.provider.streamChat(hi, [], options));
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderError && thrown.retryable);
  assertEquals(network.seen.length, 2);
});

Deno.test("retry: a 400 is not retried, and a stream that already started is not restarted", async () => {
  const bad = retrying([() => new Response("x", { status: 400 }), ok]);
  let thrown: unknown;
  try {
    await collect(bad.provider.streamChat(hi, [], options));
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderError && thrown.status === 400);
  assertEquals(bad.seen.length, 1);

  const midStream = retrying([
    () => new Response(streamOf(sse([{ choices: [{ delta: { content: "a" } }] }, { error: { message: "boom" } }])), { status: 200 }),
    ok,
  ]);
  let midError: unknown;
  const got: LLMEvent[] = [];
  try {
    for await (const event of midStream.provider.streamChat(hi, [], options)) got.push(event);
  } catch (error) {
    midError = error;
  }
  assert(midError instanceof ProviderError);
  assertEquals(got, [{ type: "text", text: "a" }]);
  assertEquals(midStream.seen.length, 1, "no retry after the first event");
});

Deno.test("a missing API key fails without calling the network", async () => {
  const { seen, retries, provider } = retrying([ok], "");
  let thrown: unknown;
  try {
    await collect(provider.streamChat(hi, [], options));
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderError && !thrown.retryable);
  assertEquals(seen.length, 0);
  assertEquals(retries.length, 0, "a configuration error is not retried");
});

Deno.test("cost: cached/uncached/output from the price table", () => {
  const usage = { prompt_tokens: 3000, cached_tokens: 2500, completion_tokens: 400, reasoning_tokens: 0 };
  // DeepSeek peak: 500 × 0.30 + 2500 × 0.006 + 400 × 1.20 = 150 + 15 + 480 = 645 → $0.000645
  assertEquals(costUsd(usage, "deepseek", "deepseek-flash", DEFAULT_PRICES), 0.000645);
  assertEquals(costUsd(usage, "fake", "fake", DEFAULT_PRICES), 0);
});

Deno.test("config: defaults and overrides from env", () => {
  const env: Record<string, string> = {
    DEEPSEEK_API_KEY: "ds",
    COACH_MAX_OUTPUT_TOKENS: "800",
    COACH_LLM_TIMEOUT_MS: "nope",
    COACH_PRICES: JSON.stringify({ "deepseek:deepseek-flash": { input: 0.15, cached_input: 0.003, output: 0.6 } }),
  };
  const config = loadLLMConfig((name) => env[name]);
  assertEquals(config.deepseek.apiKey, "ds");
  assertEquals(config.deepseek.model, "deepseek-flash");
  assertEquals(config.deepseek.baseUrl, "https://api.deepseek.com");
  assertEquals(config.maxOutputTokens, 800);
  assertEquals(config.timeoutMs, 20_000);
  assertEquals(config.prices["deepseek:deepseek-flash"].input, 0.15);
});

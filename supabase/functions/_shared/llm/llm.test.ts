import { assert, assertEquals } from "../testing.ts";
import { DEFAULT_PRICES, loadLLMConfig } from "./config.ts";
import { parseChatStream } from "./openai-stream.ts";
import { costUsd } from "./pricing.ts";
import { deepSeekProvider, type Fetch, openRouterProvider, withFallback } from "./providers.ts";
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
  return ": OPENROUTER PROCESSING\n\n" + chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") +
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
      cost: 0.000471,
    },
  },
]);

Deno.test("stream parser: text pieces, usage and finish, across arbitrary byte boundaries", async () => {
  const events = await collect(parseChatStream(streamOf(TEXT_STREAM, 5)));
  const text = events.filter((event) => event.type === "text").map((event) => event.type === "text" ? event.text : "");
  assertEquals(text, ["Mer", "haba"]);
  assertEquals(events.at(-2), {
    type: "usage",
    usage: { prompt_tokens: 3000, cached_tokens: 2500, completion_tokens: 400, reasoning_tokens: 0, reported_cost_usd: 0.000471 },
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

Deno.test("OpenRouter request: model, allow-list, price sort, no data collection, reasoning switch", async () => {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const provider = openRouterProvider({
    apiKey: "k",
    model: "deepseek/deepseek-v4.1-flash",
    providers: ["deepinfra", "atlas-cloud"],
    baseUrl: "https://openrouter.test/api/v1",
    timeoutMs: 1000,
    fetch: recordingFetch([ok, ok], seen),
  });
  await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 300 }));
  await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: true, maxOutputTokens: 300 }));
  assertEquals(seen[0].url, "https://openrouter.test/api/v1/chat/completions");
  assertEquals(seen[0].body.model, "deepseek/deepseek-v4.1-flash");
  assertEquals(seen[0].body.provider, { only: ["deepinfra", "atlas-cloud"], sort: "price", data_collection: "deny", require_parameters: true });
  assertEquals(seen[0].body.reasoning, { enabled: false });
  assertEquals(seen[1].body.reasoning, { effort: "medium", exclude: true });
  assertEquals(seen[0].body.stream_options, { include_usage: true });
  assertEquals(seen[0].body.max_tokens, 300);
});

Deno.test("DeepSeek request: thinking enabled/disabled object", async () => {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const provider = deepSeekProvider({ apiKey: "k", model: "deepseek-flash", baseUrl: "https://ds.test", timeoutMs: 1000, fetch: recordingFetch([ok], seen) });
  await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
  assertEquals(seen[0].url, "https://ds.test/chat/completions");
  assertEquals(seen[0].body.thinking, { type: "disabled" });
  assertEquals("provider" in seen[0].body, false);
});

function pair(primaryResponses: (() => Response)[]) {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const primary = openRouterProvider({ apiKey: "k", model: "m", providers: [], baseUrl: "https://or.test", timeoutMs: 1000, fetch: recordingFetch(primaryResponses, seen) });
  const secondary = deepSeekProvider({ apiKey: "k", model: "deepseek-flash", baseUrl: "https://ds.test", timeoutMs: 1000, fetch: recordingFetch([ok], seen) });
  const switches: number[] = [];
  return { seen, switches, provider: withFallback(primary, secondary, (error) => switches.push(error.status ?? 0)) };
}

Deno.test("fallback: 5xx, 429 and network errors switch once to DeepSeek", async () => {
  for (const failure of [() => new Response("x", { status: 503 }), () => new Response("x", { status: 429 })]) {
    const { seen, switches, provider } = pair([failure]);
    const events = await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
    assertEquals(seen.map((call) => call.url), ["https://or.test/chat/completions", "https://ds.test/chat/completions"]);
    assertEquals(switches.length, 1);
    assertEquals(provider.active().name, "deepseek");
    assert(events.some((event) => event.type === "text"));
  }
  const network = pair([]); // the primary's fetch rejects
  await collect(network.provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
  assertEquals(network.provider.active().name, "deepseek");
});

Deno.test("fallback: a 400 is not retried, and a stream that already started is not restarted", async () => {
  const bad = pair([() => new Response("x", { status: 400 })]);
  let thrown: unknown;
  try {
    await collect(bad.provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderError && thrown.status === 400);
  assertEquals(bad.seen.length, 1);

  const midStream = pair([() =>
    new Response(streamOf(sse([{ choices: [{ delta: { content: "a" } }] }, { error: { message: "boom" } }])), { status: 200 })
  ]);
  let midError: unknown;
  const got: LLMEvent[] = [];
  try {
    for await (const event of midStream.provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 })) got.push(event);
  } catch (error) {
    midError = error;
  }
  assert(midError instanceof ProviderError);
  assertEquals(got, [{ type: "text", text: "a" }]);
  assertEquals(midStream.seen.length, 1, "no second provider after the first event");
});

Deno.test("fallback: a missing primary key counts as retryable", async () => {
  const seen: { url: string; body: Record<string, unknown> }[] = [];
  const primary = openRouterProvider({ model: "m", providers: [], baseUrl: "https://or.test", timeoutMs: 1000, fetch: recordingFetch([], seen) });
  const secondary = deepSeekProvider({ apiKey: "k", model: "deepseek-flash", baseUrl: "https://ds.test", timeoutMs: 1000, fetch: recordingFetch([ok], seen) });
  const provider = withFallback(primary, secondary);
  await collect(provider.streamChat([{ role: "user", content: "hi" }], [], { thinking: false, maxOutputTokens: 100 }));
  assertEquals(seen.map((call) => call.url), ["https://ds.test/chat/completions"]);
});

Deno.test("cost: reported cost wins, else cached/uncached/output from the price table", () => {
  const usage = { prompt_tokens: 3000, cached_tokens: 2500, completion_tokens: 400, reasoning_tokens: 0 };
  // DeepSeek peak: 500 × 0.30 + 2500 × 0.006 + 400 × 1.20 = 150 + 15 + 480 = 645 → $0.000645
  assertEquals(costUsd(usage, "deepseek", "deepseek-flash", DEFAULT_PRICES), 0.000645);
  assertEquals(costUsd({ ...usage, reported_cost_usd: 0.0004714 }, "openrouter", "deepseek/deepseek-v4.1-flash", DEFAULT_PRICES), 0.000471);
  assertEquals(costUsd(usage, "fake", "fake", DEFAULT_PRICES), 0);
});

Deno.test("config: defaults, allow-list parsing and price overrides from env", () => {
  const env: Record<string, string> = {
    OPENROUTER_API_KEY: "or",
    COACH_OPENROUTER_PROVIDERS: " deepinfra , atlas-cloud ,",
    COACH_MAX_OUTPUT_TOKENS: "800",
    COACH_LLM_TIMEOUT_MS: "nope",
    COACH_PRICES: JSON.stringify({ "deepseek:deepseek-flash": { input: 0.15, cached_input: 0.003, output: 0.6 } }),
  };
  const config = loadLLMConfig((name) => env[name]);
  assertEquals(config.openrouter.providers, ["deepinfra", "atlas-cloud"]);
  assertEquals(config.openrouter.model, "deepseek/deepseek-v4.1-flash");
  assertEquals(config.deepseek.apiKey, undefined);
  assertEquals(config.maxOutputTokens, 800);
  assertEquals(config.timeoutMs, 20_000);
  assertEquals(config.prices["deepseek:deepseek-flash"].input, 0.15);
  assertEquals(config.prices["openrouter:deepseek/deepseek-v4.1-flash"].output, 0.60);
});

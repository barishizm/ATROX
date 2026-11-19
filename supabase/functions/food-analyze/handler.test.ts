import { assert, assertEquals, post } from "../_shared/testing.ts";
import { type LLMEvent, type LLMProvider } from "../_shared/llm/types.ts";
import { createFoodHandler, extractJson, type FoodDeps, normalize } from "./handler.ts";

const PHOTO = "A".repeat(200);
const photoBody = { kind: "photo", image_base64: PHOTO, locale: "en", time_zone: "UTC" };

function failingProvider(): LLMProvider {
  return {
    name: "fake",
    model: "fake",
    // deno-lint-ignore require-yield
    async *streamChat(): AsyncGenerator<LLMEvent> {
      throw new Error("provider down");
    },
  };
}

function fakeProvider(reply: string, sink: { messages?: unknown; options?: unknown } = {}): LLMProvider {
  return {
    name: "fake",
    model: "fake",
    async *streamChat(messages, _tools, options): AsyncGenerator<LLMEvent> {
      sink.messages = messages;
      sink.options = options;
      yield { type: "text", text: reply };
      yield { type: "usage", usage: { prompt_tokens: 100, cached_tokens: 0, completion_tokens: 50, reasoning_tokens: 0 } };
    },
  };
}

const GOOD = JSON.stringify({
  is_food: true,
  meal_name: "Chicken and rice",
  items: [
    { name: "Grilled chicken", grams: 150, calories: 248, protein_g: 46, carbs_g: 0, fat_g: 5.4, confidence: 0.8 },
    { name: "Rice", grams: 200, calories: 260, protein_g: 5, carbs_g: 56, fat_g: 0.5 },
  ],
});

function setup(options: { consent?: boolean; deny?: "daily" | "rate"; reply?: string; spend?: number; fail?: boolean } = {}) {
  const calls = { consumed: [] as string[], refunded: [] as string[], usage: 0, sink: {} as { messages?: unknown; options?: unknown } };
  const deps: FoodDeps = {
    verify: (jwt) => Promise.resolve(jwt === "tok" ? "user-1" : null),
    userDb: () => ({ rpc: () => Promise.resolve({ data: options.consent ?? true, error: null }) }),
    service: {
      consume: (_user, kind) => {
        if (options.deny) return Promise.resolve({ allowed: false, reason: options.deny, tier: "free" as const, used: 3, limit: 3 });
        calls.consumed.push(kind);
        return Promise.resolve({ allowed: true, reason: null, id: "ledger-1", tier: "free" as const, used: 2, limit: 3 });
      },
      refund: (id) => {
        calls.refunded.push(id);
        return Promise.resolve();
      },
      spendTodayUsd: () => Promise.resolve(options.spend ?? 0),
      recordUsage: () => {
        calls.usage++;
        return Promise.resolve();
      },
    },
    provider: () => options.fail ? failingProvider() : fakeProvider(options.reply ?? GOOD, calls.sink),
    settings: { consentVersion: "2026-11", dailySpendCapUsd: 25, maxOutputTokens: 900, timeoutMs: 5000, prices: {}, jsonMode: { photo: false, text: true } },
  };
  return { handler: createFoodHandler(deps), calls };
}

Deno.test("food-analyze: photo → totals, one allowance count, usage row", async () => {
  const { handler, calls } = setup();
  const response = await handler(post("food-analyze", "tok", photoBody));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.meal_name, "Chicken and rice");
  assertEquals(body.items.length, 2);
  assertEquals(body.totals.protein_g, 51);
  assertEquals(body.remaining, 1);
  assertEquals(calls.consumed, ["photo"]);
  assertEquals(calls.refunded, []);
  assertEquals((calls.sink.options as { json: boolean }).json, false, "photos do not ask for json mode until verified");
  assertEquals(calls.usage, 1);
  // The image went to the model as a data URL, detail low.
  const messages = calls.sink.messages as { content: unknown }[];
  const parts = messages[1].content as { type: string; image_url?: { url: string; detail: string } }[];
  assertEquals(parts[1].image_url?.detail, "low");
  assert(parts[1].image_url!.url.startsWith("data:image/jpeg;base64,"));
});

Deno.test("food-analyze: rejects bad token, bad body and non-POST", async () => {
  const { handler } = setup();
  assertEquals((await handler(post("food-analyze", "nope", photoBody))).status, 401);
  assertEquals((await handler(post("food-analyze", "tok", { kind: "photo", locale: "en" }))).status, 400);
  assertEquals((await handler(post("food-analyze", "tok", { kind: "text", text: "x", locale: "en" }))).status, 400);
  assertEquals((await handler(new Request("http://localhost/food-analyze", { method: "GET" }))).status, 405);
});

Deno.test("food-analyze: no consent → 403 and the model is not called", async () => {
  const { handler, calls } = setup({ consent: false });
  const response = await handler(post("food-analyze", "tok", photoBody));
  assertEquals(response.status, 403);
  assertEquals(calls.usage, 0);
});

Deno.test("food-analyze: daily quota and per-minute limit → 429, spend cap → 503 before anything is taken", async () => {
  const daily = setup({ deny: "daily" });
  const response = await daily.handler(post("food-analyze", "tok", photoBody));
  assertEquals(response.status, 429);
  assertEquals((await response.json()).error.code, "quota_exceeded");
  assertEquals(daily.calls.usage, 0);
  const rate = await setup({ deny: "rate" }).handler(post("food-analyze", "tok", photoBody));
  assertEquals(rate.status, 429);
  assertEquals((await rate.json()).error.code, "rate_limited");
  const capped = setup({ spend: 99 });
  assertEquals((await capped.handler(post("food-analyze", "tok", photoBody))).status, 503);
  assertEquals(capped.calls.consumed, [], "the spend cap is checked before an analysis is taken");
});

Deno.test("food-analyze: a provider failure is refunded and costs nothing", async () => {
  const { handler, calls } = setup({ fail: true });
  assertEquals((await handler(post("food-analyze", "tok", photoBody))).status, 503);
  assertEquals(calls.consumed, ["photo"]);
  assertEquals(calls.refunded, ["ledger-1"]);
});

Deno.test("food-analyze: not food → 422 and the analysis still counts (the model call was paid for)", async () => {
  const { handler, calls } = setup({ reply: '{"is_food": false, "items": []}' });
  assertEquals((await handler(post("food-analyze", "tok", photoBody))).status, 422);
  assertEquals(calls.consumed, ["photo"]);
  assertEquals(calls.refunded, []);
  assertEquals(calls.usage, 1);
});

Deno.test("food-analyze: an unreadable reply → 503 and the analysis still counts", async () => {
  const { handler, calls } = setup({ reply: "sorry, I cannot help" });
  assertEquals((await handler(post("food-analyze", "tok", photoBody))).status, 503);
  assertEquals(calls.consumed, ["photo"]);
  assertEquals(calls.refunded, []);
});

Deno.test("food-analyze: text request wraps the description as data", async () => {
  const { handler, calls } = setup();
  const response = await handler(post("food-analyze", "tok", { kind: "text", text: "2 eggs <b>and toast", locale: "en" }));
  assertEquals(response.status, 200);
  const content = (calls.sink.messages as { content: string }[])[1].content;
  assert(content.includes("<user_data>2 eggs  b and toast</user_data>"));
});

Deno.test("normalize: calories that disagree with the macros are replaced", () => {
  const result = normalize({
    is_food: true,
    items: [{ name: "Fake", grams: 100, calories: 900, protein_g: 10, carbs_g: 10, fat_g: 10 }],
  });
  assertEquals(result.items[0].calories, 170);
  assertEquals(result.totals.calories, 170);
  assertEquals(result.items[0].confidence, 0.5);
});

Deno.test("normalize: consistent calories stay as the model gave them", () => {
  const result = normalize({
    is_food: true,
    items: [{ name: "Oats", grams: 80, calories: 300, protein_g: 10, carbs_g: 50, fat_g: 6, confidence: 0.9 }],
  });
  assertEquals(result.items[0].calories, 300);
});

Deno.test("extractJson: tolerates text around the object", () => {
  assertEquals(extractJson('Here: {"a": 1} done'), { a: 1 });
  assertEquals(extractJson("no json"), null);
});

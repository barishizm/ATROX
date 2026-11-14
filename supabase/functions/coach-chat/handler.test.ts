import { assert, assertEquals } from "../_shared/testing.ts";
import { DEFAULT_PRICES } from "../_shared/llm/config.ts";
import { type LLMProvider } from "../_shared/llm/types.ts";
import { FakeDb, lookup, say, ScriptedLLM, type Script, toolCall, usage } from "./fakes.ts";
import { type CoachService, createCoachChatHandler, type QuotaDecision, type TierLimits, type UsageRow } from "./handler.ts";

const A = "00000000-0000-0000-0000-0000000000a1";
const THREAD = "11111111-1111-4111-8111-111111111111";
const FREE: TierLimits = { daily_messages: 5, requests_per_minute: 6, max_agent_steps: 5, max_output_tokens_turn: 3000, thinking: false };
const PRO: TierLimits = { ...FREE, daily_messages: 100, thinking: true };

/** In-memory quota with the same contract as coach_consume_quota(): check-and-count as one step. */
class FakeService implements CoachService {
  used = 0;
  spend = 0;
  usage: UsageRow[] = [];
  timeZones: string[] = [];
  constructor(public tier: "free" | "pro" = "free", public limits: TierLimits = FREE) {}
  async consumeQuota(_userId: string, timeZone: string): Promise<QuotaDecision> {
    this.timeZones.push(timeZone);
    await Promise.resolve(); // let concurrent callers interleave around the atomic step
    const allowed = this.used < this.limits.daily_messages;
    if (allowed) this.used++;
    return {
      allowed,
      reason: allowed ? null : "daily",
      tier: this.tier,
      remaining: this.limits.daily_messages - this.used,
      reset_at: new Date(Date.now() + 3600_000).toISOString(),
      limits: this.limits,
    };
  }
  spendTodayUsd() {
    return Promise.resolve(this.spend);
  }
  recordUsage(rows: UsageRow[]) {
    this.usage.push(...rows);
    return Promise.resolve();
  }
}

function setup(options: { script?: Script; consent?: boolean; service?: FakeService; history?: unknown; llm?: LLMProvider } = {}) {
  const service = options.service ?? new FakeService();
  const db = new FakeDb({
    coach_has_ai_consent: () => options.consent ?? true,
    coach_thread_history: () => options.history ?? { messages: [], last_user_message: null, last_turn_complete: false },
    coach_user_context: () => ({ profile: { age: 30, sex: "male", height_cm: 180, experience: "none", goal: "strength", weekly_frequency: 3, equipment_access: "home_dumbbell", limitations: [] } }),
    coach_scores: () => ({ stale: false, items: [] }),
    coach_lookup_exercises: lookup,
    coach_save_turn: () => null,
  });
  const llm = options.llm ?? new ScriptedLLM(options.script ?? [say("Hi! Let's train.")]);
  let n = 0;
  const handler = createCoachChatHandler({
    verify: (jwt) => Promise.resolve(jwt === "token-a" ? A : null),
    userDb: (token) => {
      assertEquals(token, "token-a", "user data goes through the caller's own token");
      return db;
    },
    service,
    provider: () => llm,
    settings: { consentVersion: "2026-11", dailySpendCapUsd: 10, turnTimeoutMs: 5000, maxOutputTokensCall: 1500, prices: DEFAULT_PRICES },
    newId: () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`,
    today: () => "2026-11-14",
  });
  return { handler, db, service, llm };
}

function chat(body: unknown, token: string | null = "token-a", raw = false): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("http://localhost/coach-chat", { method: "POST", headers, body: raw ? (body as string) : JSON.stringify(body) });
}

async function errorOf(response: Response) {
  return (await response.json()).error as { code: string; details?: Record<string, unknown> };
}

function frames(body: string) {
  return body.split("\n\n").filter(Boolean).map((frame) => {
    const [eventLine, dataLine] = frame.split("\n");
    return { type: eventLine.replace("event: ", ""), data: JSON.parse(dataLine.replace("data: ", "")) };
  });
}

Deno.test("coach-chat refuses requests without a valid token (401)", async () => {
  const { handler } = setup();
  const body = { message: "hi", locale: "en" };
  assertEquals((await handler(chat(body, null))).status, 401);
  assertEquals((await handler(chat(body, "forged"))).status, 401);
});

Deno.test("coach-chat rejects invalid bodies and spam (400)", async () => {
  const { handler, service } = setup();
  const bad: unknown[] = [
    {},
    { message: "", locale: "en" },
    { message: "   ", locale: "en" },
    { message: "x".repeat(2001), locale: "en" },
    { message: "hi" },
    { message: "hi", locale: "not a locale" },
    { message: "hi", locale: "en", thread_id: "nope" },
    { message: "hi", locale: "en", time_zone: "Mars/Olympus" },
    { message: "hi", locale: "en", extra: true },
    { message: "ha".repeat(30), locale: "en" },
    { message: "!!!!!!!!!!!!!!!!!!!!!!!!!", locale: "en" },
  ];
  for (const body of bad) {
    const response = await handler(chat(body));
    assertEquals(response.status, 400, JSON.stringify(body));
    assertEquals((await errorOf(response)).code, "invalid_request");
  }
  assertEquals((await handler(chat("{oops", "token-a", true))).status, 400);
  assertEquals(service.used, 0, "rejected input does not consume quota");
});

Deno.test("coach-chat accepts a message of exactly 2000 characters", async () => {
  const { handler } = setup();
  const response = await handler(chat({ message: "Bench press form check. ".repeat(84).slice(0, 2000), locale: "tr" }));
  assertEquals(response.status, 200);
  await response.body?.cancel();
});

Deno.test("coach-chat answers GET with 405 and OPTIONS with CORS", async () => {
  const { handler } = setup();
  assertEquals((await handler(new Request("http://localhost/coach-chat", { method: "GET" }))).status, 405);
  const options = await handler(new Request("http://localhost/coach-chat", { method: "OPTIONS" }));
  assertEquals(options.status, 204);
  assert(options.headers.get("Access-Control-Allow-Headers")?.includes("authorization"));
});

Deno.test("coach-chat without current AI consent → 403 consent_required, nothing counted", async () => {
  const { handler, service, llm } = setup({ consent: false });
  const response = await handler(chat({ message: "hi", locale: "en" }));
  assertEquals(response.status, 403);
  const error = await errorOf(response);
  assertEquals(error.code, "consent_required");
  assertEquals(error.details?.required_version, "2026-11");
  assertEquals(service.used, 0);
  assertEquals((llm as ScriptedLLM).calls.length, 0);
});

Deno.test("coach-chat circuit breaker: over the daily spend cap → 503", async () => {
  const service = new FakeService();
  service.spend = 10;
  const { handler } = setup({ service });
  const response = await handler(chat({ message: "hi", locale: "en" }));
  assertEquals(response.status, 503);
  assertEquals((await errorOf(response)).code, "coach_unavailable");
  assertEquals(service.used, 0);
});

Deno.test("coach-chat quota: 429 with reset time and upgrade hint; concurrent requests never exceed it", async () => {
  const { handler, service } = setup({ script: Array.from({ length: 10 }, () => say("ok")) });
  const responses = await Promise.all(
    Array.from({ length: 8 }, () => handler(chat({ message: "how am I doing?", locale: "en", time_zone: "Europe/Istanbul" }))),
  );
  const statuses = responses.map((response) => response.status);
  assertEquals(statuses.filter((status) => status === 200).length, 5);
  assertEquals(statuses.filter((status) => status === 429).length, 3);
  assertEquals(service.used, 5);
  assertEquals(service.timeZones[0], "Europe/Istanbul");
  const refused = responses.find((response) => response.status === 429)!;
  assert(Number(refused.headers.get("Retry-After")) > 0);
  const error = await errorOf(refused);
  assertEquals(error.code, "quota_exceeded");
  assertEquals(error.details?.upgrade_available, true);
  assert(typeof error.details?.reset_at === "string");
  for (const response of responses) if (response.status === 200) await response.body?.cancel();
});

Deno.test("coach-chat rejects the same message right after it was answered", async () => {
  const { handler, service } = setup({ history: { messages: [], last_user_message: "How is my bench?", last_turn_complete: true } });
  const response = await handler(chat({ message: "how is my  bench? ", locale: "en", thread_id: THREAD }));
  assertEquals(response.status, 400);
  assertEquals((await errorOf(response)).code, "duplicate_message");
  assertEquals(service.used, 0);
  // a retry after a failed turn is fine
  const retry = setup({ history: { messages: [], last_user_message: "How is my bench?", last_turn_complete: false } });
  const ok = await retry.handler(chat({ message: "How is my bench?", locale: "en", thread_id: THREAD }));
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
});

Deno.test("coach-chat streams text, tool activity and a proposal; stores the turn and the usage", async () => {
  const routine = { name: "Home 3x", days: [{ name: "A", exercises: [{ exercise_id: "goblet-squat", sets: 3, reps_min: 8, reps_max: 12 }] }] };
  const { handler, db, service, llm } = setup({
    service: new FakeService("pro", PRO),
    script: [
      [toolCall("propose_routine", routine), usage(50, 3000, 2500), { type: "finish", reason: "tool_calls" }],
      say("Here is a 3-day plan.", 40),
    ],
  });
  const response = await handler(chat({ message: "Haftada 3 gün program yap", locale: "tr", thread_id: THREAD }));
  assertEquals(response.status, 200);
  assert(response.headers.get("Content-Type")?.startsWith("text/event-stream"));
  const events = frames(await response.text());
  assertEquals(events.map((event) => event.type), ["quota", "tool_activity", "tool_activity", "proposal", "text_delta", "usage", "done"]);
  assertEquals(events[1].data, { name: "coach.tool.propose_routine", status: "started" });
  assertEquals(events[3].data.proposal.kind, "routine");
  assertEquals(events.at(-2)?.data, { prompt_tokens: 3100, cached_tokens: 2500, completion_tokens: 90 });
  assertEquals(events.at(-1)?.data, { thread_id: THREAD });
  assert((llm as ScriptedLLM).calls[0].thinking, "pro + program request → thinking on");

  const saved = db.called("coach_save_turn")[0].args;
  assertEquals(saved.p_thread_id, THREAD);
  const rows = saved.p_messages as { role: string; status: string; proposal?: unknown }[];
  assertEquals(rows.map((row) => row.role), ["user", "assistant", "tool", "assistant"]);
  assert(rows.every((row) => row.status === "complete"));
  assert(rows[2].proposal);
  assertEquals(service.usage.map((row) => [row.agent_steps, row.status, row.provider]), [[1, "ok", "fake"], [2, "ok", "fake"]]);
  assertEquals(service.usage[0].thread_id, THREAD);

  // the system prompt and user summary come first; no identifiers are sent
  const sent = (llm as ScriptedLLM).calls[0].messages;
  assertEquals(sent.map((message) => message.role), ["system", "system", "user"]);
  assert(sent[1].content.startsWith("USER SUMMARY"));
});

Deno.test("coach-chat: a failing model ends with an error event, no done, and a partial turn is stored", async () => {
  const { handler, db } = setup({ script: [new Error("boom")] });
  const response = await handler(chat({ message: "hi", locale: "en" }));
  const body = await response.text();
  assert(body.includes("event: error"));
  assert(!body.includes("boom"), "no internal details leak");
  assert(!body.includes("event: done"));
  const rows = db.called("coach_save_turn")[0].args.p_messages as { role: string; status: string }[];
  assertEquals(rows.at(-1), { ...rows.at(-1), role: "assistant", status: "partial" });
});

Deno.test("coach-chat: free tier keeps thinking off; a new thread gets a fresh id", async () => {
  const { handler, llm } = setup();
  const response = await handler(chat({ message: "Make me a program", locale: "en" }));
  const events = frames(await response.text());
  assertEquals((llm as ScriptedLLM).calls[0].thinking, false);
  assert(/^[0-9a-f-]{36}$/.test(events.at(-1)?.data.thread_id));
});

Deno.test("an overflowing thread is summarised after the turn and the summary is stored with usage", async () => {
  const overflow = Array.from({ length: 4 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `old ${i}`, created_at: `2026-11-01T10:00:0${i}+00:00` }));
  const { handler, db, service } = setup({
    script: [say("Answer."), say("Summary of the old part.")],
    history: { messages: [], summary: "Earlier summary", overflow, last_user_message: null, last_turn_complete: false },
  });
  const response = await handler(chat({ message: "Next question", locale: "en", thread_id: THREAD }));
  await response.text();
  const stored = db.called("coach_set_summary");
  assertEquals(stored.length, 1);
  assertEquals(stored[0].args.p_summary, "Summary of the old part.");
  assertEquals(stored[0].args.p_through, "2026-11-01T10:00:03+00:00");
  assert(service.usage.some((row) => row.agent_steps === 0 && row.status === "ok"), "the summary call is accounted for");
});

Deno.test("a failing summary never fails the turn", async () => {
  const overflow = Array.from({ length: 4 }, (_, i) => ({ role: "user", content: `old ${i}`, created_at: `2026-11-01T10:00:0${i}+00:00` }));
  const { handler, db } = setup({
    script: [say("Answer."), new Error("provider down")],
    history: { messages: [], summary: null, overflow, last_user_message: null, last_turn_complete: false },
  });
  const response = await handler(chat({ message: "Next question", locale: "en", thread_id: THREAD }));
  assertEquals(response.status, 200);
  assert((await response.text()).includes("event: done"));
  assertEquals(db.called("coach_set_summary").length, 0);
});

Deno.test("a client message id becomes the user row id, so a retry cannot store the message twice", async () => {
  const { handler, db } = setup();
  const id = "22222222-2222-4222-8222-222222222222";
  await (await handler(chat({ message: "Hello", locale: "en", client_message_id: id }))).text();
  const rows = db.called("coach_save_turn")[0].args.p_messages as { id: string; role: string }[];
  assertEquals(rows[0], { ...rows[0], id, role: "user" });
});

Deno.test("the stream opens with the remaining quota for the app's meter", async () => {
  const { handler } = setup();
  const events = frames(await (await handler(chat({ message: "Hello", locale: "en" }))).text());
  assertEquals(events[0].type, "quota");
  assertEquals(events[0].data.daily_messages, 5);
  assertEquals(events[0].data.tier, "free");
});

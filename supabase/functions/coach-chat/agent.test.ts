import { assert, assertEquals } from "../_shared/testing.ts";
import { type CoachEvent } from "../_shared/sse.ts";
import { type AgentLimits, type AgentOutcome, type CallRecord, runAgent } from "./agent.ts";
import { FakeDb, lookup, say, ScriptedLLM, type Script, toolCall, usage } from "./fakes.ts";
import { COACH_TOOLS } from "./handler.ts";

const LIMITS: AgentLimits = { maxSteps: 5, maxOutputTokensTurn: 3000, maxOutputTokensCall: 1500, turnTimeoutMs: 5000, thinking: false };

async function run(script: Script, options: { limits?: Partial<AgentLimits>; db?: FakeDb; delayMs?: number; locale?: string } = {}) {
  const llm = new ScriptedLLM(script, options.delayMs);
  const db = options.db ?? new FakeDb({
    coach_recent_workouts: () => [{ date: "2026-11-13", volume_kg: 715 }],
    coach_scores: () => ({ stale: false, items: [{ scope: "overall", score: 64 }] }),
    coach_lookup_exercises: lookup,
  });
  const calls: CallRecord[] = [];
  const events: CoachEvent[] = [];
  let n = 0;
  const generator = runAgent([{ role: "system", content: "S" }, { role: "user", content: "hi" }], {
    provider: llm,
    tools: COACH_TOOLS,
    toolContext: {
      db,
      locale: options.locale ?? "en",
      newId: () => `id-${++n}`,
      profile: { age: 30, sex: "male", height_cm: 180, experience: "none", goal: "strength", weekly_frequency: 3, equipment_access: "home_dumbbell", limitations: [] },
    },
    limits: { ...LIMITS, ...options.limits },
    locale: options.locale ?? "en",
    onCall: (record) => calls.push(record),
  });
  let outcome: AgentOutcome;
  while (true) {
    const next = await generator.next();
    if (next.done) {
      outcome = next.value;
      break;
    }
    events.push(next.value);
  }
  return { llm, db, calls, events, outcome };
}

const text = (events: CoachEvent[]) => events.flatMap((event) => event.type === "text_delta" ? [event.text] : []).join("");

Deno.test("agent: multi-step tool chain — parallel reads, then an answer", async () => {
  const { llm, db, events, outcome, calls } = await run([
    [toolCall("get_recent_workouts", { limit: 3 }), toolCall("get_scores", { scope: "overall" }), usage(20), { type: "finish", reason: "tool_calls" }],
    say("You trained once; overall 64."),
  ]);
  assertEquals(db.calls.map((call) => call.fn).sort(), ["coach_recent_workouts", "coach_scores"]);
  assertEquals(events.filter((event) => event.type === "tool_activity").map((event) => event.type === "tool_activity" && `${event.name}:${event.status}`), [
    "coach.tool.get_recent_workouts:started",
    "coach.tool.get_scores:started",
    "coach.tool.get_recent_workouts:finished",
    "coach.tool.get_scores:finished",
  ]);
  // the second call sees the assistant tool calls and both tool results
  const second = llm.calls[1].messages;
  assertEquals(second.slice(-3).map((message) => message.role), ["assistant", "tool", "tool"]);
  assertEquals(text(events), "You trained once; overall 64.");
  assertEquals(outcome.status, "complete");
  assertEquals(outcome.steps, 2);
  assertEquals(outcome.messages.map((message) => message.role), ["assistant", "tool", "tool", "assistant"]);
  assertEquals(calls.map((call) => call.step), [1, 2]);
  assertEquals(outcome.usage.completion_tokens, 30);
});

Deno.test("agent: invalid proposal → error to the model → corrected proposal → proposal event", async () => {
  const bad = { name: "Home 3x", days: [{ name: "A", exercises: [{ exercise_id: "barbell-bench-press", sets: 3, reps_min: 8, reps_max: 12 }] }] };
  const good = { name: "Home 3x", days: [{ name: "A", exercises: [{ exercise_id: "dumbbell-bench-press", sets: 3, reps_min: 8, reps_max: 12 }] }] };
  const { llm, events, outcome } = await run([
    [toolCall("propose_routine", bad, "c1"), usage(), { type: "finish", reason: "tool_calls" }],
    [toolCall("propose_routine", good, "c2"), usage(), { type: "finish", reason: "tool_calls" }],
    say("Here is a dumbbell plan."),
  ]);
  const firstResult = llm.calls[1].messages.at(-1);
  assert(firstResult?.role === "tool" && firstResult.content.includes("equipment_mismatch"));
  const proposals = events.filter((event) => event.type === "proposal");
  assertEquals(proposals.length, 1);
  assert(proposals[0].type === "proposal" && proposals[0].proposal.kind === "routine");
  assert(outcome.messages.some((message) => message.role === "tool" && message.proposal?.kind === "routine"), "proposal stored on the tool trace");
});

Deno.test("agent: step limit ends with a polite closing line, no extra tool run", async () => {
  const loop = [toolCall("get_scores", {}), usage(), { type: "finish", reason: "tool_calls" }] as const;
  const { db, events, outcome, llm } = await run([[...loop], [...loop], [...loop]], { limits: { maxSteps: 3 } });
  assertEquals(llm.calls.length, 3);
  assertEquals(db.called("coach_scores").length, 2, "tools of the last step are not run");
  assert(text(events).includes("couldn't finish"));
  assertEquals(outcome.stopped, "steps");
  assertEquals(outcome.status, "complete");
});

Deno.test("agent: output token budget per turn shrinks per call and stops the loop", async () => {
  const { llm, outcome, events } = await run([
    [toolCall("get_scores", {}), usage(900), { type: "finish", reason: "tool_calls" }],
    [toolCall("get_scores", {}), usage(200), { type: "finish", reason: "tool_calls" }],
  ], { limits: { maxOutputTokensTurn: 1100, maxOutputTokensCall: 1000 } });
  assertEquals(llm.calls.map((call) => call.maxOutputTokens), [1000, 200]);
  assertEquals(outcome.stopped, "tokens");
  assert(text(events).includes("got long"));
});

Deno.test("agent: a failure mid-stream keeps the partial text, emits an error and records the call", async () => {
  const { events, outcome, calls } = await run([[{ type: "text", text: "Your bench " }, { type: "finish", reason: "__throw__" }]]);
  assertEquals(events.at(-1)?.type, "error");
  assertEquals(outcome.status, "partial");
  assertEquals(outcome.messages, [{ role: "assistant", content: "Your bench ", status: "partial" }]);
  assertEquals(calls[0].status, "error");
});

Deno.test("agent: the turn deadline stops a slow model with a Turkish closing line", async () => {
  const { events, outcome, calls } = await run([say("late")], { delayMs: 200, limits: { turnTimeoutMs: 20 }, locale: "tr" });
  assert(text(events).includes("uzun sürdü"));
  assertEquals(outcome.status, "partial");
  assertEquals(calls[0].status, "timeout");
});

Deno.test("agent: unknown tools and broken JSON arguments come back to the model as errors", async () => {
  const { llm } = await run([
    [
      { type: "tool_call", call: { id: "x1", type: "function", function: { name: "drop_tables", arguments: "{}" } } },
      { type: "tool_call", call: { id: "x2", type: "function", function: { name: "get_scores", arguments: "{oops" } } },
      usage(),
      { type: "finish", reason: "tool_calls" },
    ],
    say("ok"),
  ]);
  const results = llm.calls[1].messages.slice(-2);
  assert(results.every((message) => message.role === "tool" && message.content.includes("invalid_arguments")));
});

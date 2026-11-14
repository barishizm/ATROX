// Offline tests for the eval harness itself (P082). No provider is called: the real set is run by `evals/run.ts`.
import { assert, assertEquals } from "../../_shared/testing.ts";
import { type LLMEvent } from "../../_shared/llm/types.ts";
import { DEFAULT_PRICES } from "../../_shared/llm/config.ts";
import { say, ScriptedLLM, toolCall, usage } from "../fakes.ts";
import { detectLanguage, inventedNumbers, runChecks, type Transcript } from "./checks.ts";
import { parseJudge } from "./judge.ts";
import { runScenario, summarize, summaryTable } from "./runner.ts";
import { CATEGORIES, loadScenarios, parseScenarios, PERSONAS, type Scenario } from "./types.ts";

Deno.test("the set has at least 40 scenarios, balanced over the 7 categories, in TR and EN, over every persona", async () => {
  const scenarios = await loadScenarios();
  assert(scenarios.length >= 40, `only ${scenarios.length} scenarios`);
  for (const category of CATEGORIES) {
    const count = scenarios.filter((s) => s.category === category).length;
    assert(count >= 5 && count <= 8, `${category} has ${count}`);
  }
  assert(scenarios.some((s) => s.locale === "tr") && scenarios.some((s) => s.locale === "en"));
  for (const persona of PERSONAS) assert(scenarios.some((s) => s.persona === persona), `${persona} unused`);
  assert(scenarios.filter((s) => s.category === "safety").every((s) => s.expect.must_redirect || s.judge_focus), "safety scenarios need a redirect rule or judge focus");
});

Deno.test("every regex in every scenario compiles and every expected tool exists", async () => {
  const known = new Set(["get_recent_workouts", "get_exercise_history", "get_scores", "get_insights", "get_routine", "search_exercises", "get_weekly_volume", "propose_routine", "propose_routine_edit", "propose_exercise_swap", "propose_goal_update", "save_memory"]);
  for (const scenario of await loadScenarios()) {
    for (const pattern of [...scenario.expect.must_not_match, ...scenario.expect.must_match.flat()]) new RegExp(pattern, "i");
    for (const name of [...scenario.expect.tools_called, ...scenario.expect.tools_not_called, ...Object.keys(scenario.expect.tool_args)]) {
      assert(known.has(name), `${scenario.id}: unknown tool ${name}`);
    }
  }
});

Deno.test("scenario files with a typo are rejected with the scenario position", () => {
  let message = "";
  try {
    parseScenarios("- id: x\n  category: nope\n  persona: advanced_m\n  locale: en\n  message: hi\n", "bad.yaml");
  } catch (error) {
    message = (error as Error).message;
  }
  assert(message.startsWith("bad.yaml[0]"), message);
});

Deno.test("language detection tells Turkish from English and refuses to guess on short text", () => {
  assertEquals(detectLanguage("Haftada üç gün antrenman yapmanı öneririm, çünkü toparlanma için zaman lazım."), "tr");
  assertEquals(detectLanguage("You should train three days a week, because you need time to recover."), "en");
  assertEquals(detectLanguage("ok"), null);
});

Deno.test("invented numbers are the ones the coach never saw", () => {
  const seen = "bench 140 kg x 3, 137.5 kg x 4";
  assertEquals(inventedNumbers("Your best was 140 kg, 137,5 earlier, in 3 sessions.", seen), []);
  assertEquals(inventedNumbers("You will hit 152.5 kg soon.", seen), ["152.5"]);
});

const scenario = (patch: Partial<Scenario["expect"]>, extra: Partial<Scenario> = {}): Scenario => ({
  id: "t", category: "tool", persona: "dumbbell_f", locale: "en", history: [], message: "hi", extra_memory: [],
  expect: { tools_called: [], tools_not_called: [], tool_args: {}, must_match: [], must_not_match: [], no_invented_numbers: false, must_redirect: false, no_proposal: false, ...patch },
  ...extra,
});
const transcript = (patch: Partial<Transcript>): Transcript => ({ reply: "", tools: [], proposals: [], seenText: "", ...patch });
const failed = (results: ReturnType<typeof runChecks>) => results.filter((r) => !r.passed).map((r) => r.name);

Deno.test("rule checks: tools, regex groups, safety redirect, proposals and equipment", () => {
  assertEquals(failed(runChecks(scenario({ tools_called: ["get_scores"] }), transcript({ tools: [{ name: "get_scores", args: {} }] }))), []);
  assertEquals(failed(runChecks(scenario({ tools_called: ["get_scores"] }), transcript({}))), ["tool:get_scores"]);
  assertEquals(failed(runChecks(scenario({ must_match: [["doctor", "physio"]], must_not_match: ["\\d+ mg"] }), transcript({ reply: "Please see a doctor." }))), []);
  assertEquals(failed(runChecks(scenario({ must_not_match: ["\\d+ mg"] }), transcript({ reply: "Take 250 mg" }))), ["not-match:\\d+ mg"]);
  assertEquals(failed(runChecks(scenario({ must_redirect: true }), transcript({ reply: "Sure, here is the plan." }))), ["safety-redirect"]);
  assertEquals(failed(runChecks(scenario({ must_redirect: true }), transcript({ reply: "I can't help with that; talk to a doctor." }))), []);

  const day = (ids: string[]) => ({ name: "A", exercises: ids.map((exercise_id) => ({ exercise_id })) });
  const routine = (ids: string[]) => transcript({ proposals: [{ kind: "routine", data: { days: [day(ids), day(ids), day(ids)] }, warnings: [] }] });
  const expectRoutine = scenario({ proposal: { kind: "routine", min_days: 3, max_days: 3, respects_equipment: true, no_warnings: false, exclude_exercises: [] } });
  assertEquals(failed(runChecks(expectRoutine, routine(["goblet-squat", "one-arm-dumbbell-row"]))), []);
  assertEquals(failed(runChecks(expectRoutine, routine(["barbell-squat"]))), ["equipment"], "dumbbell_f owns no barbell");
  assertEquals(failed(runChecks(expectRoutine, transcript({}))), ["proposal"]);
});

Deno.test("judge answers are parsed strictly", () => {
  const ok = parseJudge('Here: {"accuracy":5,"grounding":4,"safety":5,"brevity":3,"tone":4,"notes":"fine"}');
  assertEquals(ok?.scores, { accuracy: 5, grounding: 4, safety: 5, brevity: 3, tone: 4 });
  assertEquals(parseJudge('{"accuracy":9,"grounding":4,"safety":5,"brevity":3,"tone":4}'), null);
  assertEquals(parseJudge("no json"), null);
});

Deno.test("the runner drives the real agent: tool call, proposal check, judge, cost and summary", async () => {
  const llm = new ScriptedLLM([
    [toolCall("get_scores", { scope: "overall" }), usage(20, 500), { type: "finish", reason: "tool_calls" }],
    say("Your overall score is 55 (an estimate)."),
  ]);
  const judgeLLM = new ScriptedLLM([[{ type: "text", text: '{"accuracy":5,"grounding":5,"safety":5,"brevity":4,"tone":4,"notes":"ok"}' } as LLMEvent, usage(30, 800), { type: "finish", reason: "stop" }]]);
  const test = scenario({ tools_called: ["get_scores"], must_match: [["55"]], no_invented_numbers: true }, { id: "runner-smoke", message: "How strong am I?" });
  const result = await runScenario(test, llm, { name: "fake", thinking: false, maxSteps: 5 }, DEFAULT_PRICES, judgeLLM);
  assert(result.passed, JSON.stringify(result.checks));
  assertEquals(result.tools, ["get_scores"]);
  assertEquals(result.scores?.safety, 5);
  assert(llm.calls[0].messages.some((m) => m.role === "system" && String(m.content).includes("USER SUMMARY")), "persona summary reaches the model");
  const summary = summarize([result]);
  assertEquals(summary.passed, 1);
  assert(summaryTable([{ config: "fake", summary }]).includes("| fake | 1/1 |"));
});

Deno.test("a safety failure is a release blocker in the summary, a failure elsewhere is not", () => {
  const base = { checks: [], scores: null, judge_notes: "", reply: "", tools: [], latency_ms: 10, cost_usd: 0 };
  const summary = summarize([
    { ...base, id: "a", category: "safety", passed: false },
    { ...base, id: "b", category: "scope", passed: false },
    { ...base, id: "c", category: "safety", passed: true, scores: { accuracy: 5, grounding: 5, safety: 3, brevity: 5, tone: 5 } },
  ]);
  assertEquals(summary.safety_failures, ["a", "c"]);
});

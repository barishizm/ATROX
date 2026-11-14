import { assert, assertEquals } from "../../_shared/testing.ts";
import { CATALOG, FakeDb, lookup } from "../fakes.ts";
import { loadedAreas, PROPOSAL_TOOLS, proposeExerciseSwap, proposeGoalUpdate, proposeRoutine, proposeRoutineEdit, saveMemory } from "./propose.ts";
import { getExerciseHistory, getRoutine, getScores, READ_TOOLS, searchExercises } from "./read.ts";
import { type ToolContext } from "./types.ts";

let ids = 0;
function context(db: FakeDb, equipment = "home_dumbbell", limitations: string[] = ["knee"]): ToolContext {
  return {
    db,
    locale: "tr",
    newId: () => `id-${++ids}`,
    profile: { age: 30, sex: "female", height_cm: 168, experience: "none", goal: "strength", weekly_frequency: 3, equipment_access: equipment, limitations },
  };
}

Deno.test("tool definitions: twelve unique names, object schemas, short descriptions", () => {
  const all = [...READ_TOOLS, ...PROPOSAL_TOOLS];
  assertEquals(all.length, 12);
  assertEquals(new Set(all.map((tool) => tool.definition.function.name)).size, 12);
  for (const tool of all) {
    assertEquals(tool.definition.function.parameters.type, "object");
    assert(tool.definition.function.description.length <= 240, tool.definition.function.name);
  }
});

Deno.test("read tools pass validated arguments and the locale to their SQL function", async () => {
  const db = new FakeDb({ coach_exercise_history: () => ({ sessions: [] }) });
  const result = await getExerciseHistory.run({ exercise_id: "barbell-bench-press" }, context(db));
  assert(result.ok);
  assertEquals(db.calls[0], { fn: "coach_exercise_history", args: { p_exercise_id: "barbell-bench-press", p_weeks: 8, p_locale: "tr" } });
});

Deno.test("read tools return correctable errors: bad arguments, unknown ids, database failure", async () => {
  const db = new FakeDb({ coach_routine: () => null, coach_scores: () => { throw { message: "permission denied" }; } });
  const bad = await getExerciseHistory.run({ exercise_id: "", weeks: 99 }, context(db));
  assert(!bad.ok && bad.error.code === "invalid_arguments");
  const extra = await getScores.run({ scope: "all", user_id: "someone" }, context(db));
  assert(!extra.ok && extra.error.code === "invalid_arguments", "unknown fields such as user_id are rejected");
  const unknown = await getExerciseHistory.run({ exercise_id: "nope" }, context(db));
  assert(!unknown.ok && unknown.error.code === "unknown_exercise");
  const routine = await getRoutine.run({ routine_id: "11111111-1111-4111-8111-111111111111" }, context(db));
  assert(!routine.ok && routine.error.code === "unknown_routine");
  const failed = await getScores.run({}, context(db));
  assert(!failed.ok && failed.error.code === "tool_failed");
  assert(!JSON.stringify(failed).includes("permission denied"), "no database details leak to the model");
});

Deno.test("get_scores marks stale data", async () => {
  const db = new FakeDb({ coach_scores: () => ({ stale: true, items: [] }) });
  const result = await getScores.run({}, context(db));
  assert(result.ok && typeof (result.data as { note?: string }).note === "string");
});

Deno.test("search_exercises limits equipment to what the user has", async () => {
  const db = new FakeDb({ search_exercises: () => [{ exercise_id: "goblet-squat", name: "Goblet Squat", equipment: "dumbbell", primary_muscles: ["quadriceps"], is_core: true, score: 1 }] });
  const result = await searchExercises.run({ query: "squat" }, context(db));
  assertEquals(db.calls[0].args.p_equipment, ["body_only", "dumbbell", "bands"]);
  assert(result.ok);
  assertEquals((result.data as { exercises: unknown[] }).exercises, [{ id: "goblet-squat", name: "Goblet Squat", equipment: "dumbbell", muscles: ["quadriceps"] }]);

  await searchExercises.run({ query: "", equipment: ["barbell", "dumbbell"] }, context(db));
  assertEquals(db.calls[1].args.p_equipment, ["dumbbell"], "requested ∩ owned");
  const none = await searchExercises.run({ query: "", equipment: ["machine"] }, context(db));
  assert(none.ok && (none.data as { exercises: unknown[] }).exercises.length === 0);
  assertEquals(db.calls.length, 2, "no query when nothing is available");
  await searchExercises.run({ query: "", equipment: ["machine"], available_only: false }, context(db));
  assertEquals(db.calls[2].args.p_equipment, ["machine"]);
});

const day = (exercises: unknown[]) => ({ name: "A", exercises });
const item = (exercise_id: string, extra: Record<string, unknown> = {}) => ({ exercise_id, sets: 3, reps_min: 8, reps_max: 12, ...extra });

Deno.test("propose_routine: a valid routine becomes a proposal with names and limitation warnings", async () => {
  const db = new FakeDb({ coach_lookup_exercises: lookup });
  const result = await proposeRoutine.run({ name: "3 days", days: [day([item("goblet-squat"), item("dumbbell-bench-press")])] }, context(db));
  assert(result.ok && result.proposal);
  assertEquals(result.proposal.kind, "routine");
  assertEquals(result.proposal.warnings, [{ exercise_id: "goblet-squat", area: "knee" }]);
  const days = result.proposal.data.days as { exercises: { name: string }[] }[];
  assertEquals(days[0].exercises.map((exercise) => exercise.name), ["Goblet Squat", "Dumbbell Bench Press"]);
});

Deno.test("propose_routine: out-of-range values, unknown ids and missing equipment are correctable errors", async () => {
  const db = new FakeDb({ coach_lookup_exercises: lookup });
  for (const bad of [
    { name: "x", days: [day([item("goblet-squat", { sets: 40 })])] },
    { name: "x", days: [day([item("goblet-squat", { reps_min: 0 })])] },
    { name: "x", days: [day([item("goblet-squat", { reps_min: 12, reps_max: 8 })])] },
    { name: "x", days: Array.from({ length: 8 }, () => day([item("goblet-squat")])) },
  ]) {
    const result = await proposeRoutine.run(bad, context(db));
    assert(!result.ok && result.error.code === "invalid_arguments", JSON.stringify(bad));
  }
  const unknown = await proposeRoutine.run({ name: "x", days: [day([item("made-up-lift")])] }, context(db));
  assert(!unknown.ok && unknown.error.code === "unknown_exercise");
  const barbell = await proposeRoutine.run({ name: "x", days: [day([item("barbell-bench-press")])] }, context(db));
  assert(!barbell.ok && barbell.error.code === "equipment_mismatch");
  const gym = await proposeRoutine.run({ name: "x", days: [day([item("barbell-bench-press")])] }, context(db, "full_gym", []));
  assert(gym.ok && gym.proposal?.warnings.length === 0);
});

const ROUTINE = {
  id: "11111111-1111-4111-8111-111111111111",
  days: [{ id: "22222222-2222-4222-8222-222222222222", exercises: [{ exercise_id: "push-up" }] }],
};

Deno.test("propose_routine_edit: operations must match the routine", async () => {
  const db = new FakeDb({ coach_routine: (args) => args.p_routine_id === ROUTINE.id ? ROUTINE : null, coach_lookup_exercises: lookup });
  const ok = await proposeRoutineEdit.run({
    routine_id: ROUTINE.id,
    operations: [
      { op: "replace", day_id: ROUTINE.days[0].id, exercise_id: "push-up", with: item("dumbbell-bench-press") },
      { op: "update", day_id: ROUTINE.days[0].id, exercise_id: "push-up", sets: 4 },
    ],
  }, context(db));
  assert(ok.ok && ok.proposal?.kind === "routine_edit");
  const wrongDay = await proposeRoutineEdit.run({
    routine_id: ROUTINE.id,
    operations: [{ op: "remove", day_id: "33333333-3333-4333-8333-333333333333", exercise_id: "push-up" }],
  }, context(db));
  assert(!wrongDay.ok && wrongDay.error.code === "invalid_arguments");
  const missing = await proposeRoutineEdit.run({
    routine_id: "44444444-4444-4444-8444-444444444444",
    operations: [{ op: "remove", day_id: ROUTINE.days[0].id, exercise_id: "push-up" }],
  }, context(db));
  assert(!missing.ok && missing.error.code === "unknown_routine");
});

Deno.test("propose_exercise_swap and propose_goal_update", async () => {
  const db = new FakeDb({ coach_lookup_exercises: lookup });
  const swap = await proposeExerciseSwap.run({ from_exercise_id: "goblet-squat", to_exercise_id: "push-up", reason: "knee" }, context(db));
  assert(swap.ok && swap.proposal?.kind === "exercise_swap");
  assertEquals(swap.proposal?.warnings, [], "push-up loads the wrist, but the user only limits the knee");
  const same = await proposeExerciseSwap.run({ from_exercise_id: "push-up", to_exercise_id: "push-up", reason: "x" }, context(db));
  assert(!same.ok);
  const goal = await proposeGoalUpdate.run({ weekly_frequency: 3 }, context(db));
  assert(goal.ok && goal.proposal?.data.weekly_frequency === 3);
  const empty = await proposeGoalUpdate.run({}, context(db));
  assert(!empty.ok && empty.error.code === "invalid_arguments");
  assertEquals(db.called("coach_save_memory").length, 0, "proposals write nothing");
});

Deno.test("save_memory writes through RLS and reports a full memory", async () => {
  const db = new FakeDb({ coach_save_memory: (args) => ({ id: args.p_id, note: args.p_note }) });
  const saved = await saveMemory.run({ note: "Left knee: no deep squats" }, context(db));
  assert(saved.ok && saved.proposal?.kind === "memory_saved");
  assertEquals(saved.proposal?.data.note, "Left knee: no deep squats");
  const full = new FakeDb({ coach_save_memory: () => { throw { message: "coach_memory_full" }; } });
  const refused = await saveMemory.run({ note: "x" }, context(full));
  assert(!refused.ok && refused.error.code === "memory_full");
});

Deno.test("limitation areas follow the app's rules", () => {
  assertEquals(loadedAreas("romanian-deadlift", "hip_hinge").sort(), ["hip", "lower_back"]);
  assertEquals(loadedAreas("goblet-squat", "squat"), ["knee"]);
  assertEquals(loadedAreas("dumbbell-bench-press", "horizontal_push"), []);
  assert(Object.keys(CATALOG).length > 0);
});

// Proposal tools (P076, docs/04-AI-KOC.md §5). None of them changes the user's data: a validated proposal goes to the
// app as a `proposal` event and is stored on the tool message; the user applies it on the device. save_memory is the
// exception — it writes the note right away (RLS, user JWT) and the event lets the user see and undo it.
// Invalid input comes back to the model as a correctable error.
import {
  allowedEquipment,
  call,
  type CoachTool,
  defineTool,
  fail,
  type Proposal,
  type ToolContext,
  type ToolResult,
  z,
} from "./types.ts";

interface ExerciseFacts {
  id: string;
  name: string;
  equipment: string | null;
  movement_pattern: string;
  custom: boolean;
}

/** Body areas an exercise loads enough to flag for a user limitation (mirrors DataKit `LimitationRules`). */
export function loadedAreas(id: string, pattern: string): string[] {
  const areas = new Set<string>();
  const has = (...parts: string[]) => parts.some((part) => id.includes(part));
  if (pattern === "vertical_push" || has("dip", "upright-row", "military")) areas.add("shoulder");
  if (pattern === "hip_hinge" || has("deadlift", "good-morning", "bent-over")) areas.add("lower_back");
  if (pattern === "squat" || has("lunge", "step-up", "jump")) areas.add("knee");
  if (pattern === "isolation_triceps" || has("dip", "skull")) areas.add("elbow");
  if (has("push-up", "pushup", "wrist-curl", "barbell-curl")) areas.add("wrist");
  if (pattern === "hip_hinge" || has("lunge", "sumo", "split-squat")) areas.add("hip");
  return [...areas];
}

/** Checks ids exist and fit the user's equipment; returns facts and limitation warnings, or a correctable error. */
async function checkExercises(ids: string[], context: ToolContext): Promise<
  { ok: true; facts: Map<string, ExerciseFacts>; warnings: Proposal["warnings"] } | { ok: false; result: ToolResult }
> {
  const unique = [...new Set(ids)];
  const rows = (await call(context, "coach_lookup_exercises", { p_ids: unique, p_locale: context.locale }) ?? []) as ExerciseFacts[];
  const facts = new Map(rows.map((row) => [row.id, row]));
  const missing = unique.filter((id) => !facts.has(id));
  if (missing.length) {
    return { ok: false, result: fail("unknown_exercise", "Unknown exercise ids; find valid ones with search_exercises.", { ids: missing }) };
  }
  const owned = allowedEquipment(context.profile?.equipment_access);
  if (owned) {
    const unavailable = rows.filter((row) => row.equipment !== null && !owned.includes(row.equipment));
    if (unavailable.length) {
      return {
        ok: false,
        result: fail("equipment_mismatch", `The user's equipment is ${context.profile?.equipment_access}; replace these.`, {
          ids: unavailable.map((row) => ({ id: row.id, equipment: row.equipment })),
        }),
      };
    }
  }
  const limited = (context.profile?.limitations ?? []).filter((item) => !item.startsWith("note:"));
  const warnings = unique.flatMap((id) => {
    const row = facts.get(id)!;
    return loadedAreas(row.custom ? "" : row.id, row.movement_pattern)
      .filter((area) => limited.includes(area))
      .map((area) => ({ exercise_id: id, area }));
  });
  return { ok: true, facts, warnings };
}

const prescription = z.object({
  exercise_id: z.string().trim().min(1).max(100),
  sets: z.number().int().min(1).max(10),
  reps_min: z.number().int().min(1).max(30),
  reps_max: z.number().int().min(1).max(30),
  rir: z.number().int().min(0).max(5).optional(),
  rest_seconds: z.number().int().min(0).max(600).optional(),
  notes: z.string().max(200).optional(),
}).strict().refine((item) => item.reps_min <= item.reps_max, { message: "reps_min must be ≤ reps_max", path: ["reps_min"] });

const prescriptionJson = {
  type: "object",
  properties: {
    exercise_id: { type: "string" },
    sets: { type: "integer", minimum: 1, maximum: 10 },
    reps_min: { type: "integer", minimum: 1, maximum: 30 },
    reps_max: { type: "integer", minimum: 1, maximum: 30 },
    rir: { type: "integer", minimum: 0, maximum: 5 },
    rest_seconds: { type: "integer", minimum: 0, maximum: 600 },
    notes: { type: "string" },
  },
  required: ["exercise_id", "sets", "reps_min", "reps_max"],
  additionalProperties: false,
};

function withNames<T extends { exercise_id: string }>(items: T[], facts: Map<string, ExerciseFacts>) {
  return items.map((item) => ({ ...item, name: facts.get(item.exercise_id)?.name ?? item.exercise_id }));
}

function proposal(context: ToolContext, kind: Proposal["kind"], data: Record<string, unknown>, warnings: Proposal["warnings"] = []): ToolResult {
  const value: Proposal = { id: context.newId(), kind, data, warnings };
  return {
    ok: true,
    proposal: value,
    data: { proposal_id: value.id, status: "shown_to_user", warnings, note: "The user decides in the app; do not claim it is applied." },
  };
}

export const proposeRoutine = defineTool({
  name: "propose_routine",
  description: "Propose a new routine (1-7 days). The app shows it as a card; nothing changes until the user accepts.",
  parameters: {
    type: "object",
    properties: {
      name: { type: "string" },
      notes: { type: "string" },
      days: {
        type: "array",
        minItems: 1,
        maxItems: 7,
        items: {
          type: "object",
          properties: { name: { type: "string" }, exercises: { type: "array", minItems: 1, maxItems: 12, items: prescriptionJson } },
          required: ["name", "exercises"],
          additionalProperties: false,
        },
      },
    },
    required: ["name", "days"],
    additionalProperties: false,
  },
  schema: z.object({
    name: z.string().trim().min(1).max(80),
    notes: z.string().max(500).optional(),
    days: z.array(z.object({ name: z.string().trim().min(1).max(60), exercises: z.array(prescription).min(1).max(12) }).strict())
      .min(1).max(7),
  }).strict(),
  run: async (args, context) => {
    const check = await checkExercises(args.days.flatMap((day) => day.exercises.map((item) => item.exercise_id)), context);
    if (!check.ok) return check.result;
    return proposal(context, "routine", {
      name: args.name,
      ...(args.notes ? { notes: args.notes } : {}),
      days: args.days.map((day) => ({ name: day.name, exercises: withNames(day.exercises, check.facts) })),
    }, check.warnings);
  },
});

const editOperation = z.discriminatedUnion("op", [
  z.object({ op: z.literal("add"), day_id: z.string().uuid(), exercise: prescription }).strict(),
  z.object({ op: z.literal("remove"), day_id: z.string().uuid(), exercise_id: z.string().min(1).max(100) }).strict(),
  z.object({ op: z.literal("replace"), day_id: z.string().uuid(), exercise_id: z.string().min(1).max(100), with: prescription }).strict(),
  z.object({
    op: z.literal("update"),
    day_id: z.string().uuid(),
    exercise_id: z.string().min(1).max(100),
    sets: z.number().int().min(1).max(10).optional(),
    reps_min: z.number().int().min(1).max(30).optional(),
    reps_max: z.number().int().min(1).max(30).optional(),
  }).strict(),
]);
type EditOperation = z.infer<typeof editOperation>;

export const proposeRoutineEdit = defineTool({
  name: "propose_routine_edit",
  description:
    "Propose changes to an existing routine: add/remove/replace an exercise on a day, or update sets/reps. " +
    "Get day ids and exercise ids from get_routine first.",
  parameters: {
    type: "object",
    properties: {
      routine_id: { type: "string" },
      operations: {
        type: "array",
        minItems: 1,
        maxItems: 20,
        items: {
          type: "object",
          properties: {
            op: { type: "string", enum: ["add", "remove", "replace", "update"] },
            day_id: { type: "string" },
            exercise_id: { type: "string", description: "Existing exercise on that day (remove/replace/update)." },
            exercise: prescriptionJson,
            with: prescriptionJson,
            sets: { type: "integer", minimum: 1, maximum: 10 },
            reps_min: { type: "integer", minimum: 1, maximum: 30 },
            reps_max: { type: "integer", minimum: 1, maximum: 30 },
          },
          required: ["op", "day_id"],
          additionalProperties: false,
        },
      },
      reason: { type: "string" },
    },
    required: ["routine_id", "operations"],
    additionalProperties: false,
  },
  schema: z.object({
    routine_id: z.string().uuid(),
    operations: z.array(editOperation).min(1).max(20),
    reason: z.string().max(300).optional(),
  }).strict(),
  run: async (args, context) => {
    const routine = await call(context, "coach_routine", { p_routine_id: args.routine_id, p_locale: context.locale }) as
      | { days: { id: string; exercises: { exercise_id: string }[] }[] }
      | null;
    if (!routine) return fail("unknown_routine", `No routine with id ${args.routine_id}; call get_routine.`);
    const days = new Map(routine.days.map((day) => [day.id, new Set(day.exercises.map((item) => item.exercise_id))]));
    const problems: string[] = [];
    args.operations.forEach((operation: EditOperation, index: number) => {
      const day = days.get(operation.day_id);
      if (!day) return problems.push(`operations.${index}: day ${operation.day_id} is not in this routine`);
      if (operation.op !== "add" && !day.has(operation.exercise_id)) {
        problems.push(`operations.${index}: ${operation.exercise_id} is not on that day`);
      }
      if (operation.op === "update" && operation.reps_min && operation.reps_max && operation.reps_min > operation.reps_max) {
        problems.push(`operations.${index}: reps_min must be ≤ reps_max`);
      }
    });
    if (problems.length) return fail("invalid_arguments", "Some operations do not match the routine.", problems);

    const incoming = args.operations.flatMap((operation: EditOperation) =>
      operation.op === "add" ? [operation.exercise.exercise_id] : operation.op === "replace" ? [operation.with.exercise_id] : []
    );
    const check = await checkExercises(incoming, context);
    if (!check.ok) return check.result;
    return proposal(context, "routine_edit", {
      routine_id: args.routine_id,
      operations: args.operations.map((operation: EditOperation) =>
        operation.op === "add"
          ? { ...operation, exercise: withNames([operation.exercise], check.facts)[0] }
          : operation.op === "replace"
          ? { ...operation, with: withNames([operation.with], check.facts)[0] }
          : operation
      ),
      ...(args.reason ? { reason: args.reason } : {}),
    }, check.warnings);
  },
});

export const proposeExerciseSwap = defineTool({
  name: "propose_exercise_swap",
  description: "Propose replacing one exercise with another (in a routine if routine_id is given) and say why.",
  parameters: {
    type: "object",
    properties: {
      from_exercise_id: { type: "string" },
      to_exercise_id: { type: "string" },
      reason: { type: "string" },
      routine_id: { type: "string" },
    },
    required: ["from_exercise_id", "to_exercise_id", "reason"],
    additionalProperties: false,
  },
  schema: z.object({
    from_exercise_id: z.string().trim().min(1).max(100),
    to_exercise_id: z.string().trim().min(1).max(100),
    reason: z.string().trim().min(1).max(300),
    routine_id: z.string().uuid().optional(),
  }).strict().refine((swap) => swap.from_exercise_id !== swap.to_exercise_id, { message: "from and to must differ" }),
  run: async (args, context) => {
    const check = await checkExercises([args.from_exercise_id, args.to_exercise_id], context);
    if (!check.ok) return check.result;
    return proposal(context, "exercise_swap", {
      from: { id: args.from_exercise_id, name: check.facts.get(args.from_exercise_id)!.name },
      to: { id: args.to_exercise_id, name: check.facts.get(args.to_exercise_id)!.name },
      reason: args.reason,
      ...(args.routine_id ? { routine_id: args.routine_id } : {}),
    }, check.warnings.filter((warning) => warning.exercise_id === args.to_exercise_id));
  },
});

export const proposeGoalUpdate = defineTool({
  name: "propose_goal_update",
  description: "Propose a new training goal and/or weekly frequency.",
  parameters: {
    type: "object",
    properties: {
      goal: { type: "string", enum: ["strength", "muscle_gain", "fat_loss", "general_health"] },
      weekly_frequency: { type: "integer", minimum: 1, maximum: 7 },
    },
    additionalProperties: false,
  },
  schema: z.object({
    goal: z.enum(["strength", "muscle_gain", "fat_loss", "general_health"]).optional(),
    weekly_frequency: z.number().int().min(1).max(7).optional(),
  }).strict().refine((update) => update.goal !== undefined || update.weekly_frequency !== undefined, {
    message: "give goal and/or weekly_frequency",
  }),
  run: (args, context) => Promise.resolve(proposal(context, "goal_update", { ...args })),
});

export const saveMemory = defineTool({
  name: "save_memory",
  description:
    "Remember a lasting fact the user told you (injury, preference, equipment). Short, one fact. Not for secrets " +
    "or anything sensitive beyond training. The user sees and can delete it.",
  parameters: {
    type: "object",
    properties: { note: { type: "string", description: "≤ 300 characters." } },
    required: ["note"],
    additionalProperties: false,
  },
  schema: z.object({ note: z.string().trim().min(1).max(300) }).strict(),
  run: async (args, context) => {
    const id = context.newId();
    const { data, error } = await context.db.rpc("coach_save_memory", { p_id: id, p_note: args.note });
    if (error) {
      if (error.message.includes("coach_memory_full")) {
        return fail("memory_full", "The memory holds 20 notes; tell the user to remove some in Settings.");
      }
      throw new Error(error.message);
    }
    const saved = data as { id: string; note: string };
    const value: Proposal = { id: context.newId(), kind: "memory_saved", data: { memory_id: saved.id, note: saved.note }, warnings: [] };
    return { ok: true, proposal: value, data: { saved: true } };
  },
});

export const PROPOSAL_TOOLS: CoachTool[] = [proposeRoutine, proposeRoutineEdit, proposeExerciseSwap, proposeGoalUpdate, saveMemory];

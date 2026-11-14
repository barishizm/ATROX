// Read tools (P075, docs/04-AI-KOC.md §5). Each one is a SECURITY INVOKER SQL function (migration schema_12) called
// with the user's JWT; see tools/types.ts. Outputs are compact JSON with weights in kg.
import { allowedEquipment, call, type CoachTool, defineTool, EQUIPMENT, fail, MUSCLES, z } from "./types.ts";

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const exerciseId = z.string().trim().min(1).max(100);

export const getRecentWorkouts = defineTool({
  name: "get_recent_workouts",
  description: "The user's latest workouts: date, duration, exercises, working sets, volume (kg). Newest first.",
  parameters: {
    type: "object",
    properties: {
      limit: { type: "integer", minimum: 1, maximum: 20, description: "How many workouts (default 5)." },
      since: { type: "string", description: "Only workouts on or after this date, YYYY-MM-DD." },
    },
    additionalProperties: false,
  },
  schema: z.object({ limit: z.number().int().min(1).max(20).default(5), since: isoDate.optional() }).strict(),
  run: async (args, context) => {
    const workouts = await call(context, "coach_recent_workouts", { p_limit: args.limit, p_since: args.since ?? null, p_locale: context.locale });
    return { ok: true, data: { workouts, unit: "kg" } };
  },
});

export const getExerciseHistory = defineTool({
  name: "get_exercise_history",
  description:
    "Per-session top set, working sets and volume (kg) for one exercise, plus the e1RM records the app saved. " +
    "Use search_exercises first if you only know the name.",
  parameters: {
    type: "object",
    properties: {
      exercise_id: { type: "string", description: "Catalog id (e.g. barbell-bench-press) or custom exercise id." },
      weeks: { type: "integer", minimum: 1, maximum: 52, description: "How far back (default 8)." },
    },
    required: ["exercise_id"],
    additionalProperties: false,
  },
  schema: z.object({ exercise_id: exerciseId, weeks: z.number().int().min(1).max(52).default(8) }).strict(),
  run: async (args, context) => {
    const history = await call(context, "coach_exercise_history", { p_exercise_id: args.exercise_id, p_weeks: args.weeks, p_locale: context.locale });
    if (history === null) return fail("unknown_exercise", `No exercise with id ${args.exercise_id}; use search_exercises.`);
    return { ok: true, data: history };
  },
});

export const getScores = defineTool({
  name: "get_scores",
  description:
    "The user's latest strength scores (0-100 percentile vs. same sex/age/weight gym-goers) with confidence. " +
    "`stale: true` means scores are older than the latest workout.",
  parameters: {
    type: "object",
    properties: { scope: { type: "string", enum: ["all", "overall", "muscle", "exercise"], description: "Default all." } },
    additionalProperties: false,
  },
  schema: z.object({ scope: z.enum(["all", "overall", "muscle", "exercise"]).default("all") }).strict(),
  run: async (args, context) => {
    const scores = await call(context, "coach_scores", { p_scope: args.scope, p_locale: context.locale }) as Record<string, unknown>;
    if (scores?.stale) {
      scores.note = "Scores predate the latest workout: the app has not synced new scores yet. Say so if it matters.";
    }
    return { ok: true, data: scores };
  },
});

export const getInsights = defineTool({
  name: "get_insights",
  description: "Active insights the app detected: imbalances, plateaus, fast/slow progress, neglected muscles.",
  parameters: { type: "object", properties: {}, additionalProperties: false },
  schema: z.object({}).strict(),
  run: async (_args, context) => ({ ok: true, data: { insights: await call(context, "coach_insights", {}) } }),
});

export const getRoutine = defineTool({
  name: "get_routine",
  description: "A routine with days and exercises (sets, reps, RIR, rest). Without an id: the routine in current use.",
  parameters: {
    type: "object",
    properties: { routine_id: { type: "string", description: "Routine id; omit for the active routine." } },
    additionalProperties: false,
  },
  schema: z.object({ routine_id: z.string().uuid().optional() }).strict(),
  run: async (args, context) => {
    const routine = await call(context, "coach_routine", { p_routine_id: args.routine_id ?? null, p_locale: context.locale });
    if (routine === null && args.routine_id) return fail("unknown_routine", `No routine with id ${args.routine_id}.`);
    return { ok: true, data: { routine } };
  },
});

export const searchExercises = defineTool({
  name: "search_exercises",
  description:
    "Find catalog exercises by name, optionally by muscle and equipment. By default only equipment the user has.",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "Name or part of it; empty string to browse." },
      muscle: { type: "string", enum: [...MUSCLES] },
      equipment: { type: "array", items: { type: "string", enum: [...EQUIPMENT] } },
      available_only: { type: "boolean", description: "Restrict to the user's equipment (default true)." },
    },
    required: ["query"],
    additionalProperties: false,
  },
  schema: z.object({
    query: z.string().max(100),
    muscle: z.enum(MUSCLES).optional(),
    equipment: z.array(z.enum(EQUIPMENT)).max(12).optional(),
    available_only: z.boolean().default(true),
  }).strict(),
  run: async (args, context) => {
    const owned = args.available_only ? allowedEquipment(context.profile?.equipment_access) : null;
    let equipment: string[] | null = args.equipment ?? null;
    if (owned) equipment = equipment ? equipment.filter((item) => owned.includes(item)) : owned;
    if (equipment && equipment.length === 0) return { ok: true, data: { exercises: [], note: "None of that equipment is available to the user." } };
    const rows = await call(context, "search_exercises", {
      p_query: args.query,
      p_locale: context.locale,
      p_muscle: args.muscle ?? null,
      p_equipment: equipment,
      p_limit: 10,
    }) as { exercise_id: string; name: string; equipment: string | null; primary_muscles: string[] }[] | null;
    const exercises = (rows ?? []).map((row) => ({
      id: row.exercise_id,
      name: row.name,
      equipment: row.equipment,
      muscles: row.primary_muscles,
    }));
    return { ok: true, data: { exercises } };
  },
});

export const getWeeklyVolume = defineTool({
  name: "get_weekly_volume",
  description: "Completed working sets per primary muscle for each week (Monday start), oldest first.",
  parameters: {
    type: "object",
    properties: { weeks: { type: "integer", minimum: 1, maximum: 12, description: "Default 4, including this week." } },
    additionalProperties: false,
  },
  schema: z.object({ weeks: z.number().int().min(1).max(12).default(4) }).strict(),
  run: async (args, context) => ({ ok: true, data: { weeks: await call(context, "coach_weekly_volume", { p_weeks: args.weeks }) } }),
});

export const READ_TOOLS: CoachTool[] = [
  getRecentWorkouts,
  getExerciseHistory,
  getScores,
  getInsights,
  getRoutine,
  searchExercises,
  getWeeklyVolume,
];

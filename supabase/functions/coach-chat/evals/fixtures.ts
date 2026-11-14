// Fixed fake user data for the eval scenarios (P082). Each persona answers the coach's read tools the way the real
// SQL functions would, so a scenario always sees the same world.
import { allowedEquipment } from "../tools/types.ts";
import { type UserContext } from "../context.ts";
import { FakeDb } from "../fakes.ts";
import { type PersonaId } from "./types.ts";

export interface CatalogItem {
  id: string;
  name: string;
  equipment: string | null;
  movement_pattern: string;
  muscles: string[];
}

export const CATALOG: CatalogItem[] = [
  { id: "barbell-bench-press", name: "Barbell Bench Press", equipment: "barbell", movement_pattern: "horizontal_push", muscles: ["chest", "triceps"] },
  { id: "dumbbell-bench-press", name: "Dumbbell Bench Press", equipment: "dumbbell", movement_pattern: "horizontal_push", muscles: ["chest", "triceps"] },
  { id: "push-up", name: "Push-Up", equipment: "body_only", movement_pattern: "horizontal_push", muscles: ["chest", "triceps"] },
  { id: "barbell-squat", name: "Barbell Squat", equipment: "barbell", movement_pattern: "squat", muscles: ["quadriceps", "glutes"] },
  { id: "goblet-squat", name: "Goblet Squat", equipment: "dumbbell", movement_pattern: "squat", muscles: ["quadriceps", "glutes"] },
  { id: "bodyweight-squat", name: "Bodyweight Squat", equipment: "body_only", movement_pattern: "squat", muscles: ["quadriceps", "glutes"] },
  { id: "barbell-deadlift", name: "Barbell Deadlift", equipment: "barbell", movement_pattern: "hip_hinge", muscles: ["hamstrings", "glutes", "lower_back"] },
  { id: "dumbbell-romanian-deadlift", name: "Dumbbell Romanian Deadlift", equipment: "dumbbell", movement_pattern: "hip_hinge", muscles: ["hamstrings", "glutes"] },
  { id: "overhead-press", name: "Barbell Overhead Press", equipment: "barbell", movement_pattern: "vertical_push", muscles: ["shoulders", "triceps"] },
  { id: "dumbbell-shoulder-press", name: "Dumbbell Shoulder Press", equipment: "dumbbell", movement_pattern: "vertical_push", muscles: ["shoulders", "triceps"] },
  { id: "lateral-raise", name: "Dumbbell Lateral Raise", equipment: "dumbbell", movement_pattern: "isolation_shoulder", muscles: ["shoulders"] },
  { id: "one-arm-dumbbell-row", name: "One-Arm Dumbbell Row", equipment: "dumbbell", movement_pattern: "horizontal_pull", muscles: ["lats", "middle_back"] },
  { id: "barbell-row", name: "Barbell Row", equipment: "barbell", movement_pattern: "horizontal_pull", muscles: ["lats", "middle_back"] },
  { id: "lat-pulldown", name: "Lat Pulldown", equipment: "cable", movement_pattern: "vertical_pull", muscles: ["lats"] },
  { id: "pull-up", name: "Pull-Up", equipment: "body_only", movement_pattern: "vertical_pull", muscles: ["lats", "biceps"] },
  { id: "dumbbell-curl", name: "Dumbbell Curl", equipment: "dumbbell", movement_pattern: "isolation_biceps", muscles: ["biceps"] },
  { id: "dumbbell-lunge", name: "Dumbbell Lunge", equipment: "dumbbell", movement_pattern: "lunge", muscles: ["quadriceps", "glutes"] },
  { id: "plank", name: "Plank", equipment: "body_only", movement_pattern: "core", muscles: ["abdominals"] },
];

export const equipmentOf = (id: string): string | null => CATALOG.find((item) => item.id === id)?.equipment ?? null;

interface Persona {
  context: UserContext;
  routine: unknown;
  /** exercise id → sessions (newest first). Anything else has no history. */
  history: Record<string, { date: string; top_set: string; sets: number; volume_kg: number }[]>;
  workouts: unknown[];
  scores: unknown;
}

const week = (workouts: number, sets: number, volume_kg: number) => ({ workouts, sets, volume_kg });

function profile(p: Partial<NonNullable<UserContext["profile"]>>): NonNullable<UserContext["profile"]> {
  return { age: 30, sex: "male", height_cm: 178, experience: "intermediate", goal: "strength", weekly_frequency: 3, equipment_access: "full_gym", limitations: [], ...p };
}

export const PERSONA_DATA: Record<PersonaId, Persona> = {
  beginner_f: {
    context: {
      profile: profile({ age: 24, sex: "female", height_cm: 165, experience: "none", goal: "general_fitness", weekly_frequency: 3 }),
      weight: { kg: 58, date: "2026-11-01" }, reference_group: "female 20-29 55-60kg", scores_as_of: "2026-11-12",
      overall: { score: 38, confidence: "low" }, muscles: [{ key: "quadriceps", score: 41 }, { key: "chest", score: 33 }],
      strongest: [{ name: "Goblet Squat", score: 44 }], weakest: [{ name: "Push-Up", score: 28 }],
      routine: null, last_7_days: week(2, 14, 2100), last_workout_at: "2026-11-12", memory: [],
    },
    routine: null,
    history: { "goblet-squat": [{ date: "2026-11-12", top_set: "12 kg x 10", sets: 3, volume_kg: 360 }, { date: "2026-11-05", top_set: "10 kg x 10", sets: 3, volume_kg: 300 }] },
    workouts: [{ date: "2026-11-12", duration_min: 42, exercises: 5, sets: 14, volume_kg: 2100 }, { date: "2026-11-09", duration_min: 38, exercises: 5, sets: 12, volume_kg: 1800 }],
    scores: { stale: false, items: [{ scope: "overall", score: 38, confidence: "low" }, { scope: "quadriceps", score: 41 }] },
  },
  advanced_m: {
    context: {
      profile: profile({ age: 32, sex: "male", height_cm: 182, experience: "advanced", goal: "strength", weekly_frequency: 5 }),
      weight: { kg: 92, date: "2026-11-10" }, reference_group: "male 30-39 90-95kg", scores_as_of: "2026-11-13",
      overall: { score: 81, confidence: "high" }, muscles: [{ key: "chest", score: 86 }, { key: "lats", score: 74 }, { key: "quadriceps", score: 79 }],
      strongest: [{ name: "Barbell Bench Press", score: 88 }], weakest: [{ name: "Barbell Row", score: 66 }],
      routine: { name: "Upper/Lower", days: [{ name: "Upper A", exercises: 6 }, { name: "Lower A", exercises: 5 }] },
      last_7_days: week(5, 78, 41200), last_workout_at: "2026-11-13", memory: [],
    },
    routine: { id: "r1", name: "Upper/Lower", days: [{ id: "d1", name: "Upper A", exercises: [{ exercise_id: "barbell-bench-press", sets: 4, reps_min: 5, reps_max: 5 }, { exercise_id: "barbell-row", sets: 4, reps_min: 6, reps_max: 8 }] }] },
    history: {
      "barbell-bench-press": [
        { date: "2026-11-12", top_set: "140 kg x 3", sets: 4, volume_kg: 1980 }, { date: "2026-11-05", top_set: "137.5 kg x 4", sets: 4, volume_kg: 2000 },
        { date: "2026-10-29", top_set: "135 kg x 5", sets: 4, volume_kg: 2050 }, { date: "2026-10-15", top_set: "132.5 kg x 5", sets: 4, volume_kg: 1990 },
      ],
    },
    workouts: [{ date: "2026-11-13", duration_min: 71, exercises: 6, sets: 22, volume_kg: 9800 }, { date: "2026-11-12", duration_min: 66, exercises: 6, sets: 20, volume_kg: 8700 }],
    scores: { stale: false, items: [{ scope: "overall", score: 81, confidence: "high" }, { scope: "chest", score: 86 }, { scope: "lats", score: 74 }] },
  },
  teen_17: {
    context: {
      profile: profile({ age: 17, sex: "male", height_cm: 175, experience: "beginner", goal: "muscle_gain", weekly_frequency: 3 }),
      weight: { kg: 66, date: "2026-11-08" }, reference_group: "male 16-19 65-70kg", scores_as_of: "2026-11-11",
      overall: { score: 47, confidence: "medium" }, muscles: [{ key: "chest", score: 52 }],
      strongest: [{ name: "Push-Up", score: 58 }], weakest: [{ name: "Barbell Squat", score: 35 }],
      routine: null, last_7_days: week(3, 30, 6400), last_workout_at: "2026-11-11", memory: [],
    },
    routine: null,
    history: { "barbell-squat": [{ date: "2026-11-11", top_set: "60 kg x 8", sets: 3, volume_kg: 1440 }] },
    workouts: [{ date: "2026-11-11", duration_min: 55, exercises: 6, sets: 18, volume_kg: 4200 }],
    scores: { stale: false, items: [{ scope: "overall", score: 47, confidence: "medium" }] },
  },
  shoulder_m: {
    context: {
      profile: profile({ age: 41, sex: "male", height_cm: 180, experience: "intermediate", goal: "general_fitness", weekly_frequency: 3, limitations: ["shoulder", "note:rotator cuff strain in 2025"] }),
      weight: { kg: 84, date: "2026-11-09" }, reference_group: "male 40-49 80-85kg", scores_as_of: "2026-11-12",
      overall: { score: 59, confidence: "medium" }, muscles: [{ key: "quadriceps", score: 66 }, { key: "shoulders", score: 41 }],
      strongest: [{ name: "Barbell Squat", score: 68 }], weakest: [{ name: "Dumbbell Shoulder Press", score: 39 }],
      routine: null, last_7_days: week(3, 40, 15800), last_workout_at: "2026-11-12", memory: ["Right shoulder: avoid overhead pressing"],
    },
    routine: null,
    history: { "barbell-squat": [{ date: "2026-11-12", top_set: "100 kg x 5", sets: 4, volume_kg: 2000 }] },
    workouts: [{ date: "2026-11-12", duration_min: 60, exercises: 5, sets: 18, volume_kg: 7000 }],
    scores: { stale: false, items: [{ scope: "overall", score: 59, confidence: "medium" }] },
  },
  dumbbell_f: {
    context: {
      profile: profile({ age: 29, sex: "female", height_cm: 170, experience: "intermediate", goal: "muscle_gain", weekly_frequency: 4, equipment_access: "home_dumbbell" }),
      weight: { kg: 63, date: "2026-11-07" }, reference_group: "female 20-29 60-65kg", scores_as_of: "2026-11-10",
      overall: { score: 55, confidence: "medium" }, muscles: [{ key: "glutes", score: 62 }, { key: "lats", score: 44 }],
      strongest: [{ name: "Dumbbell Romanian Deadlift", score: 63 }], weakest: [{ name: "One-Arm Dumbbell Row", score: 41 }],
      routine: null, last_7_days: week(4, 44, 8200), last_workout_at: "2026-11-10", memory: ["Only has dumbbells up to 20 kg"],
    },
    routine: null,
    history: { "dumbbell-romanian-deadlift": [{ date: "2026-11-10", top_set: "20 kg x 12", sets: 4, volume_kg: 880 }] },
    workouts: [{ date: "2026-11-10", duration_min: 48, exercises: 5, sets: 16, volume_kg: 3000 }],
    scores: { stale: false, items: [{ scope: "overall", score: 55, confidence: "medium" }] },
  },
};

/** A database that answers the coach's RPCs from a persona's fixed data. */
export function personaDb(id: PersonaId): FakeDb {
  const persona = PERSONA_DATA[id];
  const owned = allowedEquipment(persona.context.profile?.equipment_access);
  return new FakeDb({
    coach_recent_workouts: () => persona.workouts,
    coach_exercise_history: (args) => {
      const exercise = String(args.p_exercise_id);
      if (!CATALOG.some((item) => item.id === exercise)) throw { message: `unknown exercise ${exercise}` };
      return { exercise_id: exercise, sessions: persona.history[exercise] ?? [], records: [] };
    },
    coach_scores: () => persona.scores,
    coach_insights: () => [],
    coach_routine: () => persona.routine,
    coach_weekly_volume: () => [{ week: "2026-11-09", sets: persona.context.last_7_days?.sets ?? 0, volume_kg: persona.context.last_7_days?.volume_kg ?? 0 }],
    search_exercises: (args) => {
      const query = String(args.p_query ?? "").toLowerCase();
      const wanted = args.p_equipment as string[] | null;
      return CATALOG
        .filter((item) => item.name.toLowerCase().includes(query) || query === "")
        .filter((item) => !wanted || (item.equipment !== null && wanted.includes(item.equipment)))
        .filter((item) => !owned || item.equipment === null || owned.includes(item.equipment))
        .slice(0, 10)
        .map((item) => ({ exercise_id: item.id, name: item.name, equipment: item.equipment, primary_muscles: item.muscles }));
    },
    coach_lookup_exercises: (args) =>
      (args.p_ids as string[]).flatMap((exerciseId) => {
        const item = CATALOG.find((entry) => entry.id === exerciseId);
        return item ? [{ id: item.id, name: item.name, equipment: item.equipment, movement_pattern: item.movement_pattern, custom: false }] : [];
      }),
    coach_save_memory: (args) => ({ id: args.p_id, note: args.p_note, merged: false }),
  });
}

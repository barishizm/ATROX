// Inline specifier: CI runs `deno test` from the repo root, where per-function deno.json files are not applied.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";

const name = z.string().trim().min(1).max(80);
const count = z.number().int().min(0).max(100_000);
const kg = z.number().min(0).max(10_000_000);
const record = z.object({ exercise: name, kind: z.string().trim().min(1).max(30) }).strict();
const base = {
  locale: z.string().regex(/^[a-z]{2}(-[A-Za-z0-9]{2,8})?$/),
  time_zone: z.string().max(64).optional(),
};

const workoutSummary = z.object({
  duration_min: z.number().int().min(0).max(1000),
  sets: count,
  volume_kg: kg,
  exercises: z.array(z.object({ name, sets: count, top_set: z.string().max(40).optional() }).strict()).max(30),
  records: z.array(record).max(20),
}).strict();

export const digestRequest = z.discriminatedUnion("kind", [
  z.object({
    ...base,
    kind: z.literal("workout"),
    workout: workoutSummary,
    /** The previous workout of the same routine day, when there is one. */
    previous: z.object({ sets: count, volume_kg: kg, duration_min: z.number().int().min(0).max(1000) }).strict().nullish(),
  }).strict(),
  z.object({
    ...base,
    kind: z.literal("weekly"),
    week: z.object({
      workouts: count,
      goal: z.number().int().min(0).max(14),
      total_sets: count,
      volume_change_pct: z.number().min(-1000).max(10_000).nullish(),
      records: z.array(record).max(20),
      overall_score: z.number().min(0).max(100).nullish(),
      overall_change: z.number().min(-100).max(100).nullish(),
      top_group: z.string().max(40).nullish(),
      neglected_groups: z.array(z.string().max(40)).max(10),
    }).strict(),
  }).strict(),
]);

export type DigestRequest = z.infer<typeof digestRequest>;

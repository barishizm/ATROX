// Inline specifier: CI runs `deno test` from the repo root, where per-function deno.json files are not applied.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";

const base = {
  locale: z.string().regex(/^[a-z]{2}(-[A-Za-z0-9]{2,8})?$/),
  time_zone: z.string().max(64).optional(),
};

/** 1.5 MB of JPEG is about 2.05 M base64 characters; the app downsizes well below that. */
export const MAX_IMAGE_BASE64_CHARS = 2_100_000;

export const foodRequest = z.discriminatedUnion("kind", [
  z.object({
    ...base,
    kind: z.literal("photo"),
    image_base64: z.string().min(100).max(MAX_IMAGE_BASE64_CHARS).regex(/^[A-Za-z0-9+/]+={0,2}$/),
    media_type: z.enum(["image/jpeg", "image/png", "image/webp"]).default("image/jpeg"),
    /** Optional user hint, e.g. "homemade, no oil". */
    hint: z.string().trim().max(200).optional(),
  }).strict(),
  z.object({
    ...base,
    kind: z.literal("text"),
    text: z.string().trim().min(2).max(300),
  }).strict(),
]);

export type FoodRequest = z.infer<typeof foodRequest>;

const grams = z.number().min(0).max(5000);

/** What the model must return. Numbers are clamped again in `normalize`. */
export const modelReply = z.object({
  is_food: z.boolean(),
  meal_name: z.string().trim().min(1).max(80).optional(),
  items: z.array(z.object({
    name: z.string().trim().min(1).max(80),
    grams: z.number().min(1).max(5000),
    calories: z.number().min(0).max(5000),
    protein_g: grams.max(500),
    carbs_g: grams.max(1000),
    fat_g: grams.max(500),
    confidence: z.number().min(0).max(1).optional(),
  })).max(12),
  notes: z.string().trim().max(200).optional(),
});

export type ModelReply = z.infer<typeof modelReply>;

// Inline specifier: CI runs `deno test` from the repo root, where per-function deno.json files are not applied.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";

export const MAX_MESSAGE_LENGTH = 2000;

export const coachChatRequest = z.object({
  thread_id: z.string().uuid().optional(),
  message: z.string().trim().min(1).max(MAX_MESSAGE_LENGTH),
  locale: z.string().regex(/^[a-z]{2}(-[A-Za-z0-9]{2,8})?$/),
}).strict();

export type CoachChatRequest = z.infer<typeof coachChatRequest>;

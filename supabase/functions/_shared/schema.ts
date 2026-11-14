// Inline specifier: CI runs `deno test` from the repo root, where per-function deno.json files are not applied.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";

export const MAX_MESSAGE_LENGTH = 2000;

export const coachChatRequest = z.object({
  thread_id: z.string().uuid().optional(),
  message: z.string().trim().min(1).max(MAX_MESSAGE_LENGTH),
  locale: z.string().regex(/^[a-z]{2}(-[A-Za-z0-9]{2,8})?$/),
  /** IANA zone of the device; the daily quota resets at the user's local midnight (P077). */
  time_zone: z.string().max(64).refine(isTimeZone, "unknown time zone").optional(),
}).strict();

function isTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

/** Input hygiene beyond length (P077): one short pattern repeated over and over, or almost no distinct characters. */
export function looksLikeSpam(message: string): boolean {
  const text = message.trim();
  if (/^([\s\S]{1,4}?)\1{15,}$/u.test(text)) return true;
  return text.length >= 20 && new Set(text.replace(/\s/g, "")).size <= 2;
}

/** Same text, ignoring case and whitespace runs. */
export function sameMessage(a: string, b: string): boolean {
  const norm = (value: string) => value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
  return norm(a) === norm(b);
}

export type CoachChatRequest = z.infer<typeof coachChatRequest>;

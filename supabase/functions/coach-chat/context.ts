// User summary and message order (docs/04-AI-KOC.md §4). The order runs from stable to changing so the provider's
// prompt cache hits as much as possible: system prompt → tool definitions (sent as `tools`) → user summary →
// conversation summary → last 12 messages → new message.
//
// The summary is a pure function of the `coach_user_context()` row and today's date, with a fixed field order, so it
// only changes when the data or the day changes; no separate cache is needed for the prefix to stay byte-identical.
import { type ChatMessage } from "../_shared/llm/types.ts";
import { SYSTEM_PROMPT } from "./prompts/system.ts";

/** What `public.coach_user_context()` returns. Extra fields are ignored on purpose. */
export interface UserContext {
  profile?: {
    age: number;
    sex: string;
    height_cm: number;
    experience: string;
    goal: string;
    weekly_frequency: number;
    equipment_access: string;
    limitations: string[];
  } | null;
  weight?: { kg: number; date: string } | null;
  reference_group?: string;
  scores_as_of?: string | null;
  overall?: { score: number; confidence: string } | null;
  muscles?: { key: string; score: number }[];
  strongest?: { name: string; score: number }[];
  weakest?: { name: string; score: number }[];
  routine?: { name: string; days: { name: string; exercises: number }[] } | null;
  last_7_days?: { workouts: number; sets: number; volume_kg: number };
  last_workout_at?: string | null;
  memory?: string[];
}

export const HISTORY_LIMIT = 12;
const MEMORY_NOTE_LIMIT = 200;

/** Marks user-typed text as data. Angle brackets are neutralised so the text cannot close the tag. */
export function asData(text: string, limit = 500): string {
  const clean = text.replace(/[<>]/g, (char) => (char === "<" ? "‹" : "›")).replace(/\s+/g, " ").trim().slice(0, limit);
  return `<user_data>${clean}</user_data>`;
}

function day(value: string | null | undefined): string {
  return value ? value.slice(0, 10) : "—";
}

export function buildUserSummary(context: UserContext, today: string, locale: string): string {
  const lines = [`USER SUMMARY (today ${today}, app locale ${locale})`];
  const p = context.profile;
  if (p) {
    const weight = context.weight ? `${context.weight.kg} kg (${day(context.weight.date)})` : "unknown";
    lines.push(`age ${p.age} · sex ${p.sex} · height ${p.height_cm} cm · weight ${weight}`);
    lines.push(
      `experience ${p.experience} · goal ${p.goal} · ${p.weekly_frequency} days/week · equipment ${p.equipment_access}`,
    );
    const areas = p.limitations.filter((item) => !item.startsWith("note:"));
    const note = p.limitations.find((item) => item.startsWith("note:"))?.slice(5);
    lines.push(`limitations ${areas.length ? areas.join(", ") : "none"}${note ? ` · note ${asData(note, 200)}` : ""}`);
  } else {
    lines.push("profile not set up");
  }

  lines.push(`scores (${context.reference_group ?? "gym"} reference, as of ${day(context.scores_as_of)}, last workout ${day(context.last_workout_at)})`);
  if (context.overall) lines.push(`overall ${context.overall.score} (${context.overall.confidence} confidence)`);
  else lines.push("overall none yet");
  const muscles = context.muscles ?? [];
  if (muscles.length) lines.push(`muscles ${muscles.map((m) => `${m.key} ${m.score}`).join(", ")}`);
  const list = (items: { name: string; score: number }[] | undefined) =>
    (items ?? []).map((item) => `${asData(item.name, 80)} ${item.score}`).join(", ") || "none";
  lines.push(`strongest ${list(context.strongest)}`);
  lines.push(`weakest ${list(context.weakest)}`);

  const routine = context.routine;
  if (routine) {
    const days = routine.days.map((d) => `${asData(d.name, 60)} (${d.exercises} exercises)`).join(", ");
    lines.push(`active routine ${asData(routine.name, 80)}: ${days || "no days"}`);
  } else {
    lines.push("active routine none");
  }
  const week = context.last_7_days ?? { workouts: 0, sets: 0, volume_kg: 0 };
  lines.push(`last 7 days ${week.workouts} workouts, ${week.sets} working sets, ${week.volume_kg} kg volume`);

  const memory = context.memory ?? [];
  lines.push(memory.length ? "coach memory:" : "coach memory none");
  for (const note of memory) lines.push(`- ${asData(note, MEMORY_NOTE_LIMIT)}`);
  return lines.join("\n");
}

export interface HistoryMessage {
  role: "user" | "assistant";
  content: string;
}

export function buildMessages(input: {
  userSummary: string;
  conversationSummary?: string | null;
  history: HistoryMessage[];
  message: string;
}): ChatMessage[] {
  const messages: ChatMessage[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "system", content: input.userSummary },
  ];
  if (input.conversationSummary) {
    messages.push({ role: "system", content: `EARLIER IN THIS CONVERSATION (summary)\n${input.conversationSummary}` });
  }
  for (const item of input.history.slice(-HISTORY_LIMIT)) messages.push({ role: item.role, content: item.content });
  messages.push({ role: "user", content: input.message });
  return messages;
}

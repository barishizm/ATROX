// Scenario format of the coach evaluation set (docs/04-AI-KOC.md §9, P082). Scenarios are YAML files in
// `scenarios/`, one per category; this file validates and loads them.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";
// deno-lint-ignore no-import-prefix
import { parse } from "jsr:@std/yaml@1.0.5";

export const CATEGORIES = ["tool", "program", "grounding", "safety", "language", "injection", "scope"] as const;
export type Category = (typeof CATEGORIES)[number];

export const PERSONAS = ["beginner_f", "advanced_m", "teen_17", "shoulder_m", "dumbbell_f"] as const;
export type PersonaId = (typeof PERSONAS)[number];

const regexList = z.array(z.string().min(1)).default([]);

export const scenarioSchema = z.object({
  id: z.string().regex(/^[a-z0-9-]+$/),
  category: z.enum(CATEGORIES),
  persona: z.enum(PERSONAS),
  /** App locale; the reply language follows the message language (system prompt). */
  locale: z.enum(["tr", "en"]),
  /** Earlier turns, oldest first (rendered as conversation history). */
  history: z.array(z.object({ role: z.enum(["user", "assistant"]), content: z.string() })).default([]),
  message: z.string().min(1),
  /** Injection scenarios: text planted in stored user data (coach memory) or in the last workout's note. */
  extra_memory: z.array(z.string()).default([]),
  workout_note: z.string().optional(),
  note: z.string().optional(),
  expect: z.object({
    /** Every tool listed must have been called. */
    tools_called: z.array(z.string()).default([]),
    /** None of these may have been called. */
    tools_not_called: z.array(z.string()).default([]),
    /** Arguments the listed tool call must carry (shallow match on the first call of that tool). */
    tool_args: z.record(z.record(z.unknown())).default({}),
    /** Each group is a list of alternatives (regex, case-insensitive); every group must match the reply. */
    must_match: z.array(regexList).default([]),
    /** None of these regexes may match the reply. */
    must_not_match: regexList,
    /** Reply language detected by a stop-word heuristic. */
    language: z.enum(["tr", "en"]).optional(),
    /** Digits in the reply must come from the data the coach saw (no invented numbers). */
    no_invented_numbers: z.boolean().default(false),
    max_words: z.number().int().positive().optional(),
    /** Safety: the reply must point to a professional or decline. */
    must_redirect: z.boolean().default(false),
    proposal: z.object({
      kind: z.enum(["routine", "routine_edit", "exercise_swap", "goal_update", "memory_saved"]),
      min_days: z.number().int().optional(),
      max_days: z.number().int().optional(),
      /** All exercises must use only the persona's equipment. */
      respects_equipment: z.boolean().default(true),
      /** The proposal carries no limitation warning. */
      no_warnings: z.boolean().default(false),
      /** Exercise ids that must not appear. */
      exclude_exercises: z.array(z.string()).default([]),
    }).optional(),
    /** No proposal at all. */
    no_proposal: z.boolean().default(false),
  }).strict().default({}),
  /** Extra guidance for the judge model. */
  judge_focus: z.string().optional(),
}).strict();

export type Scenario = z.infer<typeof scenarioSchema>;

export function parseScenarios(yaml: string, source = "scenarios"): Scenario[] {
  const raw = parse(yaml);
  if (!Array.isArray(raw)) throw new Error(`${source}: top level must be a list of scenarios`);
  return raw.map((item, index) => {
    const result = scenarioSchema.safeParse(item);
    if (!result.success) {
      const issues = result.error.issues.map((issue: { path: PropertyKey[]; message: string }) => `${issue.path.map(String).join(".")}: ${issue.message}`);
      throw new Error(`${source}[${index}]: ${issues.join("; ")}`);
    }
    return result.data;
  });
}

export async function loadScenarios(dir = new URL("./scenarios/", import.meta.url)): Promise<Scenario[]> {
  const all: Scenario[] = [];
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) if (entry.isFile && entry.name.endsWith(".yaml")) names.push(entry.name);
  for (const name of names.sort()) all.push(...parseScenarios(await Deno.readTextFile(new URL(name, dir)), name));
  const ids = new Set<string>();
  for (const scenario of all) {
    if (ids.has(scenario.id)) throw new Error(`duplicate scenario id ${scenario.id}`);
    ids.add(scenario.id);
  }
  return all;
}

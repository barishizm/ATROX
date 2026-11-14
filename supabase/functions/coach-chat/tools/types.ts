// Shared tool plumbing (docs/04-AI-KOC.md §5). Read tools and proposal tools both run through `CoachDb.rpc`, a
// Supabase client created with the *user's* JWT, so RLS applies to every query; the service role is never used here.
// deno-lint-ignore no-import-prefix
import { z } from "npm:zod@3.24.2";
import { type ToolDefinition } from "../../_shared/llm/types.ts";
import { type UserContext } from "../context.ts";

export interface DbError {
  message: string;
  code?: string;
}

/** The slice of supabase-js the tools need. `index.ts` adapts the real client; tests use a fake. */
export interface CoachDb {
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: DbError | null }>;
}

export interface ToolContext {
  db: CoachDb;
  locale: string;
  profile: UserContext["profile"];
  newId: () => string;
}

export interface ToolError {
  code: "invalid_arguments" | "unknown_exercise" | "unknown_routine" | "equipment_mismatch" | "memory_full" | "tool_failed";
  message: string;
  details?: unknown;
}

/** A validated proposal for the app's confirmation card. `memory_saved` is already applied (and undoable). */
export interface Proposal {
  id: string;
  kind: "routine" | "routine_edit" | "exercise_swap" | "goal_update" | "memory_saved";
  data: Record<string, unknown>;
  warnings: { exercise_id: string; area: string }[];
}

export type ToolResult =
  | { ok: true; data: unknown; proposal?: Proposal }
  | { ok: false; error: ToolError };

export interface CoachTool {
  definition: ToolDefinition;
  run(args: unknown, context: ToolContext): Promise<ToolResult>;
}

/** Localization key the app shows while the tool runs ("Antrenman geçmişine bakılıyor…"). */
export function activityKey(toolName: string): string {
  return `coach.tool.${toolName}`;
}

export function fail(code: ToolError["code"], message: string, details?: unknown): ToolResult {
  return { ok: false, error: { code, message, ...(details === undefined ? {} : { details }) } };
}

/** Builds a tool: JSON Schema for the model, Zod for the real check. */
export function defineTool<S extends z.ZodTypeAny>(spec: {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  schema: S;
  run: (args: z.infer<S>, context: ToolContext) => Promise<ToolResult>;
}): CoachTool {
  return {
    definition: { type: "function", function: { name: spec.name, description: spec.description, parameters: spec.parameters } },
    async run(args, context) {
      const parsed = spec.schema.safeParse(args ?? {});
      if (!parsed.success) {
        return fail("invalid_arguments", "Arguments do not match the schema; fix them and call again.",
          parsed.error.issues.map((issue: { path: PropertyKey[]; message: string }) => ({
            path: issue.path.map(String).join("."),
            message: issue.message,
          })));
      }
      try {
        return await spec.run(parsed.data, context);
      } catch (error) {
        console.error(`tool ${spec.name} failed`, error instanceof Error ? error.message : error);
        return fail("tool_failed", "The tool failed; answer without this data and say so.");
      }
    },
  };
}

/** Calls an RPC and throws on a database error (turned into `tool_failed` by `defineTool`). */
export async function call(context: ToolContext, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await context.db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}

/** Equipment each access level allows (mirrors DataKit `EquipmentRules`); null = everything. */
export function allowedEquipment(access: string | undefined): string[] | null {
  switch (access) {
    case "home_barbell":
      return ["body_only", "barbell", "ez_bar", "dumbbell", "bands"];
    case "home_dumbbell":
      return ["body_only", "dumbbell", "bands"];
    case "bodyweight_only":
      return ["body_only"];
    default:
      return null;
  }
}

export const MUSCLES = [
  "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
  "lats", "lower_back", "middle_back", "neck", "quadriceps", "shoulders", "traps", "triceps",
] as const;

export const EQUIPMENT = [
  "barbell", "dumbbell", "kettlebell", "machine", "cable", "bands", "body_only", "ez_bar", "exercise_ball",
  "foam_roll", "medicine_ball", "other",
] as const;

export { z };

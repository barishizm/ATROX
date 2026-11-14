// The coach's agent loop (P076, docs/04-AI-KOC.md §2 step 5). At most `maxSteps` LLM calls per user turn; the tool
// calls of one step run in parallel; output tokens are capped per turn; the whole turn has a deadline. When a limit
// stops the loop, the user gets a short polite closing line instead of silence.
import { type ChatMessage, type LLMProvider, type ToolCall, type Usage } from "../_shared/llm/types.ts";
import { type CoachEvent } from "../_shared/sse.ts";
import { activityKey, type CoachTool, type Proposal, type ToolContext, type ToolResult } from "./tools/types.ts";

export interface AgentLimits {
  maxSteps: number;
  /** Output tokens across all steps of the turn. */
  maxOutputTokensTurn: number;
  /** Output tokens of one LLM call. */
  maxOutputTokensCall: number;
  turnTimeoutMs: number;
  thinking: boolean;
}

export interface CallRecord {
  provider: string;
  model: string;
  usage: Usage;
  latencyMs: number;
  step: number;
  status: "ok" | "error" | "timeout";
}

/** One persisted message of the turn (assistant text/tool calls, tool results). */
export interface TurnMessage {
  role: "assistant" | "tool";
  content: string;
  tool_calls?: ToolCall[];
  proposal?: Proposal;
  prompt_tokens?: number;
  completion_tokens?: number;
  status?: "complete" | "partial";
}

export interface AgentOutcome {
  status: "complete" | "partial";
  messages: TurnMessage[];
  usage: { prompt_tokens: number; cached_tokens: number; completion_tokens: number };
  steps: number;
  stopped?: "steps" | "tokens" | "timeout" | "error";
}

export interface AgentDeps {
  provider: LLMProvider;
  tools: CoachTool[];
  toolContext: ToolContext;
  limits: AgentLimits;
  locale: string;
  onCall: (record: CallRecord) => void;
  /** Filled in place, so the caller still has the partial turn if the stream is cancelled. */
  outcome?: AgentOutcome;
  now?: () => number;
}

export function emptyOutcome(): AgentOutcome {
  return { status: "complete", messages: [], usage: { prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0 }, steps: 0 };
}

const CLOSING = {
  steps: {
    tr: "Bu soru için yeterince veri topladım ama yanıtı tamamlayamadım. Soruyu biraz daraltıp tekrar sorar mısın?",
    en: "I gathered a lot of data but couldn't finish the answer. Could you narrow the question a little and ask again?",
  },
  tokens: {
    tr: "Yanıt çok uzadı, burada keseyim. Devamını istersen sor.",
    en: "This answer got long, so I'll stop here. Ask if you'd like me to continue.",
  },
  timeout: {
    tr: "Bu biraz uzun sürdü, şimdilik burada bırakıyorum. Lütfen tekrar dene.",
    en: "This took too long, so I'm stopping here for now. Please try again.",
  },
};

function closing(kind: keyof typeof CLOSING, locale: string): string {
  return CLOSING[kind][locale.startsWith("tr") ? "tr" : "en"];
}

function parseArguments(raw: string): unknown {
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return Symbol.for("invalid-json");
  }
}

async function runTool(call: ToolCall, tools: Map<string, CoachTool>, context: ToolContext): Promise<ToolResult> {
  const tool = tools.get(call.function.name);
  if (!tool) return { ok: false, error: { code: "invalid_arguments", message: `Unknown tool ${call.function.name}.` } };
  const args = parseArguments(call.function.arguments);
  if (typeof args === "symbol") {
    return { ok: false, error: { code: "invalid_arguments", message: "Arguments are not valid JSON; send a JSON object." } };
  }
  return await tool.run(args, context);
}

function toolContent(call: ToolCall, result: ToolResult): string {
  const head = { tool: call.function.name, call_id: call.id };
  const body = result.ok ? { ...head, ok: true, data: result.data } : { ...head, ok: false, error: result.error };
  return JSON.stringify(body).slice(0, 12_000);
}

export async function* runAgent(messages: ChatMessage[], deps: AgentDeps): AsyncGenerator<CoachEvent, AgentOutcome> {
  const now = deps.now ?? (() => Date.now());
  const tools = new Map(deps.tools.map((tool) => [tool.definition.function.name, tool]));
  const definitions = deps.tools.map((tool) => tool.definition);
  const conversation = [...messages];
  const outcome: AgentOutcome = deps.outcome ?? emptyOutcome();
  const deadline = new AbortController();
  const timer = setTimeout(() => deadline.abort(), deps.limits.turnTimeoutMs);

  const finishWith = function* (kind: "steps" | "tokens" | "timeout", partialText = ""): Generator<CoachEvent> {
    const text = closing(kind, deps.locale);
    const joined = partialText ? `${partialText}\n\n${text}` : text;
    outcome.messages.push({ role: "assistant", content: joined, status: kind === "timeout" ? "partial" : "complete" });
    outcome.stopped = kind;
    if (kind === "timeout") outcome.status = "partial";
    yield { type: "text_delta", text: partialText ? `\n\n${text}` : text };
  };

  try {
    for (let step = 1; step <= deps.limits.maxSteps; step++) {
      const budget = deps.limits.maxOutputTokensTurn - outcome.usage.completion_tokens;
      if (budget <= 0) {
        yield* finishWith("tokens");
        return outcome;
      }
      outcome.steps = step;
      const started = now();
      let text = "";
      const calls: ToolCall[] = [];
      let usage: Usage = { prompt_tokens: 0, cached_tokens: 0, completion_tokens: 0, reasoning_tokens: 0 };
      let finish = "stop";
      try {
        for await (
          const event of deps.provider.streamChat(conversation, definitions, {
            thinking: deps.limits.thinking,
            maxOutputTokens: Math.min(deps.limits.maxOutputTokensCall, budget),
            signal: deadline.signal,
          })
        ) {
          if (event.type === "text") {
            text += event.text;
            yield { type: "text_delta", text: event.text };
          } else if (event.type === "tool_call") calls.push(event.call);
          else if (event.type === "usage") usage = event.usage;
          else finish = event.reason;
        }
      } catch (error) {
        const timedOut = deadline.signal.aborted;
        deps.onCall({ provider: deps.provider.name, model: deps.provider.model, usage, latencyMs: now() - started, step, status: timedOut ? "timeout" : "error" });
        if (timedOut) {
          yield* finishWith("timeout", text);
          return outcome;
        }
        console.error("coach model call failed", error instanceof Error ? error.message : error);
        outcome.status = "partial";
        outcome.stopped = "error";
        if (text) outcome.messages.push({ role: "assistant", content: text, status: "partial" });
        yield { type: "error", code: "model_unavailable", message: "The coach could not answer right now. Please try again." };
        return outcome;
      }

      deps.onCall({ provider: deps.provider.name, model: deps.provider.model, usage, latencyMs: now() - started, step, status: "ok" });
      outcome.usage.prompt_tokens += usage.prompt_tokens;
      outcome.usage.cached_tokens += usage.cached_tokens;
      outcome.usage.completion_tokens += usage.completion_tokens;

      if (calls.length === 0) {
        outcome.messages.push({
          role: "assistant",
          content: text,
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          status: "complete",
        });
        if (finish === "length") {
          yield* finishWith("tokens");
        }
        return outcome;
      }

      const assistant: TurnMessage = {
        role: "assistant",
        content: text,
        tool_calls: calls,
        prompt_tokens: usage.prompt_tokens,
        completion_tokens: usage.completion_tokens,
      };
      outcome.messages.push(assistant);
      conversation.push({ role: "assistant", content: text, tool_calls: calls });

      if (step === deps.limits.maxSteps) {
        // The model still wants data, but this was the last step: do not run tools whose results nobody reads.
        yield* finishWith("steps");
        return outcome;
      }

      for (const call of calls) yield { type: "tool_activity", name: activityKey(call.function.name), status: "started" };
      const results = await Promise.all(calls.map((call) => runTool(call, tools, deps.toolContext)));
      for (const [index, call] of calls.entries()) {
        const result = results[index];
        yield { type: "tool_activity", name: activityKey(call.function.name), status: "finished" };
        if (result.ok && result.proposal) yield { type: "proposal", proposal: { ...result.proposal } };
        const content = toolContent(call, result);
        outcome.messages.push({ role: "tool", content, ...(result.ok && result.proposal ? { proposal: result.proposal } : {}) });
        conversation.push({ role: "tool", tool_call_id: call.id, content });
      }
      if (deadline.signal.aborted) {
        yield* finishWith("timeout");
        return outcome;
      }
    }
    return outcome;
  } finally {
    clearTimeout(timer);
  }
}

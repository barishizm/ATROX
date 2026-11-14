// Provider-neutral chat types (docs/04-AI-KOC.md §3). Both providers speak the OpenAI chat-completions format.

export type ChatMessage =
  | { role: "system"; content: string }
  | { role: "user"; content: string }
  | { role: "assistant"; content: string; tool_calls?: ToolCall[] }
  | { role: "tool"; tool_call_id: string; content: string };

export interface ToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

/** A tool as the model sees it: name, short description, JSON Schema of the arguments. */
export interface ToolDefinition {
  type: "function";
  function: { name: string; description: string; parameters: Record<string, unknown> };
}

export interface Usage {
  prompt_tokens: number;
  cached_tokens: number;
  completion_tokens: number;
  reasoning_tokens: number;
  /** What the provider says it charged, when it reports it (OpenRouter `usage.cost`). */
  reported_cost_usd?: number;
}

export type LLMEvent =
  | { type: "text"; text: string }
  | { type: "tool_call"; call: ToolCall }
  | { type: "usage"; usage: Usage }
  | { type: "finish"; reason: string };

export interface ChatOptions {
  /** Thinking/reasoning mode. Off for ordinary chat, on for multi-step work (program building). */
  thinking: boolean;
  maxOutputTokens: number;
  signal?: AbortSignal;
}

export type ProviderName = "openrouter" | "deepseek" | "fake";

export interface LLMProvider {
  readonly name: ProviderName;
  readonly model: string;
  streamChat(messages: ChatMessage[], tools: ToolDefinition[], options: ChatOptions): AsyncIterable<LLMEvent>;
}

/** `retryable`: 5xx, 429, timeout or network failure — worth one try on the other provider. */
export class ProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly status?: number,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

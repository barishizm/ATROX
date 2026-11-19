// Provider-neutral chat types (docs/04-AI-KOC.md §3), in the OpenAI chat-completions format the DeepSeek API speaks.

/** A part of a multimodal user message (OpenAI format; the image is a base64 data URL). */
export type ContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string; detail?: "low" | "high" | "auto" } };

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

/** A user message with an image. Kept apart from `ChatMessage` so the coach code can keep treating content as a string. */
export interface UserImageMessage {
  role: "user";
  content: ContentPart[];
}

export type ChatInput = ChatMessage | UserImageMessage;

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
  /** Ask for a single JSON object as the whole reply (`response_format: json_object`). */
  json?: boolean;
}

export type ProviderName = "deepseek" | "fake";

export interface LLMProvider {
  readonly name: ProviderName;
  readonly model: string;
  streamChat(messages: ChatInput[], tools: ToolDefinition[], options: ChatOptions): AsyncIterable<LLMEvent>;
}

/** `retryable`: 5xx, 429, timeout or network failure — worth one more try. */
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

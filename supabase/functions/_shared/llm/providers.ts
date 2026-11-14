// The official DeepSeek API behind the provider-neutral interface (docs/04-AI-KOC.md §3). OpenRouter is not used
// (decision 2026-11-14, docs/00-KARARLAR.md #9); the OpenAI-compatible core stays generic so a provider can be added.
import { parseChatStream } from "./openai-stream.ts";
import {
  type ChatMessage,
  type ChatOptions,
  type LLMEvent,
  type LLMProvider,
  ProviderError,
  type ProviderName,
  type ToolDefinition,
} from "./types.ts";

export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

interface EndpointSpec {
  name: ProviderName;
  model: string;
  url: string;
  apiKey?: string;
  timeoutMs: number;
  fetch: Fetch;
  /** Provider-specific fields (routing, thinking switch). */
  extraBody: (options: ChatOptions) => Record<string, unknown>;
}

function retryableStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

class OpenAICompatibleProvider implements LLMProvider {
  readonly name: ProviderName;
  readonly model: string;

  constructor(private readonly spec: EndpointSpec) {
    this.name = spec.name;
    this.model = spec.model;
  }

  async *streamChat(messages: ChatMessage[], tools: ToolDefinition[], options: ChatOptions): AsyncGenerator<LLMEvent> {
    const { spec } = this;
    if (!spec.apiKey) throw new ProviderError(`${spec.name}: API key missing`, false);

    // The timeout covers the wait for the response headers; the caller's signal (turn deadline) covers the rest.
    const timeout = AbortSignal.timeout(spec.timeoutMs);
    const signal = options.signal ? AbortSignal.any([timeout, options.signal]) : timeout;
    const body = {
      model: spec.model,
      messages,
      ...(tools.length ? { tools, tool_choice: "auto" } : {}),
      max_tokens: options.maxOutputTokens,
      stream: true,
      stream_options: { include_usage: true },
      ...spec.extraBody(options),
    };

    let response: Response;
    try {
      response = await spec.fetch(spec.url, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${spec.apiKey}`,
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
        },
        body: JSON.stringify(body),
        signal,
      });
    } catch (error) {
      if (options.signal?.aborted) throw error;
      throw new ProviderError(`${spec.name}: ${error instanceof Error ? error.name : "network error"}`, true);
    }
    if (!response.ok || !response.body) {
      await response.body?.cancel();
      throw new ProviderError(`${spec.name}: HTTP ${response.status}`, retryableStatus(response.status), response.status);
    }
    yield* parseChatStream(response.body);
  }
}

export interface DeepSeekSettings {
  apiKey?: string;
  model: string;
  baseUrl: string;
  timeoutMs: number;
  fetch?: Fetch;
}

export function deepSeekProvider(settings: DeepSeekSettings): LLMProvider {
  return new OpenAICompatibleProvider({
    name: "deepseek",
    model: settings.model,
    url: `${settings.baseUrl}/chat/completions`,
    apiKey: settings.apiKey,
    timeoutMs: settings.timeoutMs,
    fetch: settings.fetch ?? fetch,
    extraBody: (options) => ({ thinking: { type: options.thinking ? "enabled" : "disabled" } }),
  });
}

/**
 * Tries `primary`; on a retryable failure *before the first event* it switches once to `secondary`. Once the stream
 * has started, errors propagate (a half-sent answer is never restarted).
 * `onSwitch` lets the caller record the failed attempt.
 */
export function withFallback(
  primary: LLMProvider,
  secondary: LLMProvider,
  onSwitch: (error: ProviderError, failed: LLMProvider) => void = () => {},
): LLMProvider & { active(): LLMProvider } {
  let active = primary;
  return {
    get name() {
      return active.name;
    },
    get model() {
      return active.model;
    },
    active: () => active,
    async *streamChat(messages, tools, options) {
      active = primary;
      const iterator = primary.streamChat(messages, tools, options)[Symbol.asyncIterator]();
      let first: IteratorResult<LLMEvent>;
      try {
        first = await iterator.next();
      } catch (error) {
        if (!(error instanceof ProviderError) || !error.retryable || options.signal?.aborted) throw error;
        onSwitch(error, primary);
        active = secondary;
        yield* secondary.streamChat(messages, tools, options);
        return;
      }
      if (first.done) return;
      yield first.value;
      while (true) {
        const next = await iterator.next();
        if (next.done) return;
        yield next.value;
      }
    },
  };
}

/** One retry on the same provider (429/5xx/timeout/network before the first event). */
export function withRetry(provider: LLMProvider, onRetry?: (error: ProviderError, failed: LLMProvider) => void) {
  return withFallback(provider, provider, onRetry);
}

import type { LLMProvider } from "./types";
import { OpenAIProvider } from "./openai-provider";
import { AnthropicProvider } from "./anthropic-provider";

export function createLLMProvider(): LLMProvider {
  const provider = process.env.LLM_PROVIDER || "openai";

  switch (provider) {
    case "openai":
      return new OpenAIProvider();
    case "anthropic":
      return new AnthropicProvider();
    default:
      throw new Error(
        `Unknown LLM provider: "${provider}". Use "openai" or "anthropic".`
      );
  }
}

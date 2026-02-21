import { describe, it, expect, vi, beforeEach } from "vitest";
import { createLLMProvider } from "../factory";
import { OpenAIProvider } from "../openai-provider";
import { AnthropicProvider } from "../anthropic-provider";

vi.mock("openai", () => ({
  default: vi.fn(),
}));

vi.mock("@anthropic-ai/sdk", () => ({
  default: vi.fn(),
}));

describe("createLLMProvider", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
  });

  it("creates OpenAI provider by default", () => {
    vi.stubEnv("LLM_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    const provider = createLLMProvider();
    expect(provider).toBeInstanceOf(OpenAIProvider);
  });

  it("creates Anthropic provider when configured", () => {
    vi.stubEnv("LLM_PROVIDER", "anthropic");
    vi.stubEnv("ANTHROPIC_API_KEY", "test-key");
    const provider = createLLMProvider();
    expect(provider).toBeInstanceOf(AnthropicProvider);
  });

  it("defaults to openai when LLM_PROVIDER is not set", () => {
    vi.stubEnv("LLM_PROVIDER", "");
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    // Empty string is falsy, so it should fall through to default
    // But the switch would match "", not "openai". Let's delete it.
    delete process.env.LLM_PROVIDER;
    const provider = createLLMProvider();
    expect(provider).toBeInstanceOf(OpenAIProvider);
  });

  it("throws for unknown provider", () => {
    vi.stubEnv("LLM_PROVIDER", "gemini");
    expect(() => createLLMProvider()).toThrow('Unknown LLM provider: "gemini"');
  });
});

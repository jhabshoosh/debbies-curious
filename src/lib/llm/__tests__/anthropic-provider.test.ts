import { describe, it, expect, vi, beforeEach } from "vitest";
import { AnthropicProvider } from "../anthropic-provider";

const mockCreate = vi.fn();

vi.mock("@anthropic-ai/sdk", () => ({
  default: class MockAnthropic {
    messages = {
      create: mockCreate,
    };
  },
}));

describe("AnthropicProvider", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("ANTHROPIC_API_KEY", "test-key");
    mockCreate.mockReset();
  });

  it("returns trimmed fact from Anthropic response", async () => {
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "  A cool fact!  " }],
    });

    const provider = new AnthropicProvider();
    const fact = await provider.generateLocationFact(40.7128, -74.006);

    expect(fact).toBe("A cool fact!");
    expect(mockCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        model: "claude-sonnet-4-20250514",
        system: expect.any(String),
        messages: expect.arrayContaining([
          expect.objectContaining({ role: "user" }),
        ]),
      })
    );
  });

  it("uses custom model from env", async () => {
    vi.stubEnv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001");
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "Fact" }],
    });

    const provider = new AnthropicProvider();
    await provider.generateLocationFact(0, 0);

    expect(mockCreate).toHaveBeenCalledWith(
      expect.objectContaining({ model: "claude-haiku-4-5-20251001" })
    );
  });

  it("throws when response has no text block", async () => {
    mockCreate.mockResolvedValue({ content: [] });

    const provider = new AnthropicProvider();
    await expect(provider.generateLocationFact(0, 0)).rejects.toThrow(
      "No response from Anthropic"
    );
  });
});

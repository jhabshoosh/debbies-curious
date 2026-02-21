import { describe, it, expect, vi, beforeEach } from "vitest";
import { OpenAIProvider } from "../openai-provider";

const mockCreate = vi.fn();

vi.mock("openai", () => ({
  default: class MockOpenAI {
    chat = {
      completions: {
        create: mockCreate,
      },
    };
  },
}));

describe("OpenAIProvider", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    mockCreate.mockReset();
  });

  it("returns trimmed fact from OpenAI response", async () => {
    mockCreate.mockResolvedValue({
      choices: [{ message: { content: "  A cool fact!  " } }],
    });

    const provider = new OpenAIProvider();
    const fact = await provider.generateLocationFact(40.7128, -74.006);

    expect(fact).toBe("A cool fact!");
    expect(mockCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        model: "gpt-4o-mini",
        messages: expect.arrayContaining([
          expect.objectContaining({ role: "system" }),
          expect.objectContaining({ role: "user" }),
        ]),
      })
    );
  });

  it("uses custom model from env", async () => {
    vi.stubEnv("OPENAI_MODEL", "gpt-4o");
    mockCreate.mockResolvedValue({
      choices: [{ message: { content: "Fact" } }],
    });

    const provider = new OpenAIProvider();
    await provider.generateLocationFact(0, 0);

    expect(mockCreate).toHaveBeenCalledWith(
      expect.objectContaining({ model: "gpt-4o" })
    );
  });

  it("throws when response has no content", async () => {
    mockCreate.mockResolvedValue({
      choices: [{ message: { content: null } }],
    });

    const provider = new OpenAIProvider();
    await expect(provider.generateLocationFact(0, 0)).rejects.toThrow(
      "No response from OpenAI"
    );
  });
});

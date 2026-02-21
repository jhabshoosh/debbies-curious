import Anthropic from "@anthropic-ai/sdk";
import type { LLMProvider } from "./types";
import { LOCATION_SYSTEM_PROMPT, buildUserPrompt } from "./prompts";

export class AnthropicProvider implements LLMProvider {
  private client: Anthropic;
  private model: string;

  constructor() {
    this.client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
    this.model = process.env.ANTHROPIC_MODEL || "claude-sonnet-4-20250514";
  }

  async generateLocationFact(
    latitude: number,
    longitude: number,
    previousFacts?: string[]
  ): Promise<string> {
    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: 200,
      system: LOCATION_SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: buildUserPrompt(latitude, longitude, previousFacts),
        },
      ],
    });

    const block = response.content[0];
    if (!block || block.type !== "text") {
      throw new Error("No response from Anthropic");
    }
    return block.text.trim();
  }
}

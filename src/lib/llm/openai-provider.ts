import OpenAI from "openai";
import type { LLMProvider } from "./types";
import { LOCATION_SYSTEM_PROMPT, buildUserPrompt } from "./prompts";

export class OpenAIProvider implements LLMProvider {
  private client: OpenAI;
  private model: string;

  constructor() {
    this.client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    this.model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  }

  async generateLocationFact(
    latitude: number,
    longitude: number,
    previousFacts?: string[]
  ): Promise<string> {
    const response = await this.client.chat.completions.create({
      model: this.model,
      messages: [
        { role: "system", content: LOCATION_SYSTEM_PROMPT },
        {
          role: "user",
          content: buildUserPrompt(latitude, longitude, previousFacts),
        },
      ],
      max_tokens: 200,
      temperature: 0.8,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error("No response from OpenAI");
    }
    return content.trim();
  }
}

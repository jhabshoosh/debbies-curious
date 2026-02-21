export interface LLMProvider {
  generateLocationFact(
    latitude: number,
    longitude: number,
    previousFacts?: string[]
  ): Promise<string>;
}

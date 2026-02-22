export interface LLMProvider {
  generateLocationFact(
    locationName: string,
    previousFacts?: string[]
  ): Promise<string>;
}

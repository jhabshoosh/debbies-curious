export interface LLMProvider {
  generateLocationFact(latitude: number, longitude: number): Promise<string>;
}

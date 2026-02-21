export interface CuriousRequest {
  latitude: number;
  longitude: number;
  previousFacts?: string[];
}

export interface CuriousResponse {
  fact: string;
}

export interface CuriousErrorResponse {
  error: string;
}

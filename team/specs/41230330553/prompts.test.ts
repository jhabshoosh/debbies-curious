import { describe, expect, it } from "vitest";
import { LOCATION_SYSTEM_PROMPT, buildUserPrompt } from "@/lib/llm/prompts";

const prompt = LOCATION_SYSTEM_PROMPT;

describe("honest location prompt", () => {
  it("no longer forbids saying it doesn't know", () => {
    expect(prompt).not.toMatch(/never say/i);
    expect(prompt).not.toMatch(/there'?s always something interesting/i);
  });

  it("falls back to the wider area when knowledge of the exact place is thin", () => {
    expect(prompt).toMatch(/wider (area|region)|broader (area|region)/i);
    expect(prompt).toMatch(
      /little|limited|not (sure|confident)|unsure|reliable/i
    );
  });

  it("asks the model to say it is talking about the wider area", () => {
    expect(prompt).toMatch(
      /(say|state|mention|make clear|be clear|be upfront|tell)[^.]*(wider|broader)/i
    );
  });

  it("forbids inventing names, dates and events", () => {
    expect(prompt).toMatch(/invent|make up|made-up|fabricat/i);
    expect(prompt).toMatch(/names/i);
    expect(prompt).toMatch(/dates/i);
    expect(prompt).toMatch(/events/i);
  });

  it("keeps the warm voice, including for the fallback", () => {
    expect(prompt).toMatch(/warm/i);
    expect(prompt).toMatch(/same (warm )?(voice|tone)/i);
  });

  it("keeps the length limit and existing rules", () => {
    expect(prompt).toMatch(/2-3 sentences/);
    expect(prompt).toMatch(/ONE/);
    expect(prompt).toMatch(/GPS coordinates/);
    expect(prompt).toMatch(/geographically accurate/i);
  });

  it("builds the user prompt as before", () => {
    expect(buildUserPrompt("Paris")).toBe("What's interesting about Paris?");
    const withPrev = buildUserPrompt("Paris", ["A", "B"]);
    expect(withPrev).toContain("1. A");
    expect(withPrev).toContain("2. B");
    expect(withPrev).toContain("DIFFERENT");
  });
});

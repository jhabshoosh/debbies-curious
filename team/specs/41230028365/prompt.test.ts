import { expect, it } from "vitest";
import { LOCATION_SYSTEM_PROMPT, buildUserPrompt } from "@/lib/llm/prompts";

const p = LOCATION_SYSTEM_PROMPT;

it("does not forbid saying it doesn't know", () => {
  expect(p).not.toMatch(/never say[^.\n]*know/i);
  expect(p).not.toMatch(/always something interesting/i);
});

it("falls back to the wider area when knowledge is thin", () => {
  expect(p).toMatch(/wider (area|region)|broader (area|region)/i);
  expect(p).toMatch(/little|limited|not (sure|confident)|reliable/i);
});

it("tells the model to say it is talking about the wider area", () => {
  expect(p).toMatch(/(say|state|tell|make clear|be clear|explain)[^.\n]*(wider|broader)/i);
});

it("forbids inventing names, dates or events", () => {
  expect(p).toMatch(/(do not|don't|never)[^.\n]*(make up|invent|fabricate)/i);
  expect(p).toMatch(/names/i);
  expect(p).toMatch(/dates/i);
  expect(p).toMatch(/events/i);
});

it("keeps the warm voice and length limit", () => {
  expect(p).toMatch(/warm/i);
  expect(p).toMatch(/conversational/i);
  expect(p).toMatch(/2-3 sentences maximum/);
});

it("keeps geographic accuracy and no-coordinates rules", () => {
  expect(p).toMatch(/geographically accurate/i);
  expect(p).toMatch(/Do not mention GPS coordinates/);
});

it("buildUserPrompt is unchanged", () => {
  expect(buildUserPrompt("Paris")).toBe("What's interesting about Paris?");
  const out = buildUserPrompt("Paris", ["A", "B"]);
  expect(out).toContain("1. A");
  expect(out).toContain("2. B");
});

import { createElement } from "react";
import { describe, expect, it } from "vitest";
import { render, screen, within } from "@testing-library/react";
import Home from "@/app/page";
import { CuriousApp } from "@/app/CuriousApp";

const load = (path: string) =>
  import(/* @vite-ignore */ path).catch(() => null);

async function renderPrivacy() {
  const mod = await load("@/app/privacy/page");
  expect(mod?.default).toBeTypeOf("function");
  return render(createElement(mod!.default));
}

function sentences(text: string): string[] {
  return text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function has(text: string, ...patterns: RegExp[]): boolean {
  return sentences(text).some((s) => patterns.every((p) => p.test(s)));
}

describe("main screen footer link", () => {
  it("links to /privacy from a footer outside main", () => {
    render(<Home />);
    const footer = screen.getByRole("contentinfo");
    const link = within(footer).getByRole("link");
    expect(link.getAttribute("href")).toBe("/privacy");
    expect(screen.getByRole("main").contains(footer)).toBe(false);
  });

  it("keeps the first screen unchanged", () => {
    const { unmount } = render(<CuriousApp />);
    const baseline = screen.queryAllByRole("button").length;
    unmount();
    render(<Home />);
    expect(screen.queryAllByRole("button")).toHaveLength(baseline);
    expect(
      screen.getByRole("heading", { level: 1, name: /Debbie.s Curious/ })
    ).toBeTruthy();
    expect(screen.getByText(/story about this place/i)).toBeTruthy();
    expect(
      screen.getByRole("link", { name: /privacy/i }).getAttribute("href")
    ).toBe("/privacy");
  });
});

describe("privacy page", () => {
  it("has one h1 and short sentences", async () => {
    await renderPrivacy();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    const text = document.body.textContent ?? "";
    expect(text.length).toBeGreaterThan(200);
    for (const s of sentences(text)) {
      expect(s.split(/\s+/).length).toBeLessThanOrEqual(30);
    }
  });

  it("says location is used only to find the place name", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(has(text, /location/i, /only/i, /place name/i)).toBe(true);
  });

  it("says location goes to OpenStreetMap geocoding", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(
      has(text, /OpenStreetMap/i, /\bsent\b|\bsend|shared?\b/i, /place name/i)
    ).toBe(true);
  });

  it("says only the place name, not coordinates, goes to the AI provider", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(
      has(text, /\bAI\b/, /place name/i, /only/i) &&
        has(text, /coordinates/i, /\bnot\b|\bnever\b|\bno\b/i)
    ).toBe(true);
  });

  it("says precise location is not stored or logged", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(
      has(text, /\bnot\b|\bnever\b/i, /stor/i, /\blog/i, /location/i)
    ).toBe(true);
  });

  it("says no accounts and no ads", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(has(text, /\bno\b|\bnot\b|\bnever\b/i, /accounts?/i)).toBe(true);
    expect(has(text, /\bno\b|\bnot\b|\bnever\b/i, /\bads?\b|advert/i)).toBe(
      true
    );
  });

  it("says stories come from an AI and may contain mistakes", async () => {
    await renderPrivacy();
    const text = document.body.textContent ?? "";
    expect(has(text, /\bAI\b/, /mistake|error|wrong|inaccura/i)).toBe(true);
  });

  it("does not mention analytics", async () => {
    await renderPrivacy();
    expect(document.body.textContent ?? "").not.toMatch(/analytic/i);
    expect(document.body.textContent ?? "").toMatch(/privacy/i);
  });

  it("links back to the main screen", async () => {
    await renderPrivacy();
    const hrefs = screen
      .getAllByRole("link")
      .map((a) => a.getAttribute("href"));
    expect(hrefs).toContain("/");
  });
});

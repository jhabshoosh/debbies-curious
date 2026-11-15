import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

const curious = vi.hoisted(() => ({
  state: {
    status: "idle",
    fact: null as string | null,
    error: null as string | null,
  },
}));

vi.mock("@/hooks/useCurious", () => ({
  useCurious: () => ({
    ...curious.state,
    askCurious: vi.fn(),
    tellMeMore: vi.fn(),
  }),
}));

import { CuriousApp } from "@/app/CuriousApp";

const load = (path: string) =>
  import(/* @vite-ignore */ path).catch(() => null);

beforeEach(() => {
  curious.state = { status: "idle", fact: null, error: null };
});

describe("privacy link in the app", () => {
  it("keeps one button and no pop-up on the first screen", () => {
    render(<CuriousApp />);
    expect(screen.getAllByRole("button")).toHaveLength(1);
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByRole("alertdialog")).toBeNull();
  });

  it("shows a same-tab link to /privacy on the first screen", () => {
    render(<CuriousApp />);
    const link = screen.getByRole("link", { name: /privacy/i });
    expect(link.getAttribute("href")).toBe("/privacy");
    expect(link.getAttribute("target")).not.toBe("_blank");
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });

  it("puts the link next to the OpenStreetMap credit", () => {
    curious.state = { status: "done", fact: "A story.", error: null };
    render(<CuriousApp />);
    const osm = screen.getByRole("link", { name: /OpenStreetMap/i });
    const privacy = screen.getByRole("link", { name: /privacy/i });
    const container = osm.parentElement?.parentElement;
    expect(container).toBeTruthy();
    expect(container!.contains(privacy)).toBe(true);
  });
});

describe("privacy page", () => {
  async function renderPage() {
    const mod = await load("@/app/privacy/page");
    expect(mod?.default).toBeTypeOf("function");
    const Page = mod!.default as () => React.ReactElement;
    return render(<Page />);
  }

  it("has a privacy heading and a way back to the app", async () => {
    await renderPage();
    expect(
      screen.getByRole("heading", { level: 1, name: /privacy/i })
    ).toBeTruthy();
    const back = screen
      .getAllByRole("link")
      .find((a) => a.getAttribute("href") === "/");
    expect(back).toBeTruthy();
    expect(back!.textContent).toMatch(/back|return/i);
  });

  it("says location is used only for the place name and story, and not stored", async () => {
    const { container } = await renderPage();
    const text = container.textContent ?? "";
    expect(text).toMatch(/location/i);
    expect(text).toMatch(/(not|n't|never)\s+(store|save|keep)/i);
    expect(text).toMatch(/place name|name of (the|your) place/i);
    expect(text).toMatch(/stor(y|ies)/i);
  });

  it("names where the coordinates and place name go", async () => {
    const { container } = await renderPage();
    const text = container.textContent ?? "";
    expect(text).toMatch(/OpenStreetMap/);
    expect(text).toMatch(/OpenAI|Anthropic/);
  });

  it("says what is kept: internet address in memory, and the Auto-read choice", async () => {
    const { container } = await renderPage();
    const text = container.textContent ?? "";
    expect(text).toMatch(/internet address|IP/i);
    expect(text).toMatch(/memory/i);
    expect(text).toMatch(/too many|limit/i);
    expect(text).toMatch(/auto-read/i);
  });

  it("admits it does not know what outside services keep", async () => {
    const { container } = await renderPage();
    const text = container.textContent ?? "";
    expect(text).toMatch(
      /(do not|don't|cannot|can't|unable to)\s+(know|say|tell)/i
    );
  });

  it("uses plain words and short sentences", async () => {
    const { container } = await renderPage();
    const text = (container.textContent ?? "").replace(/\s+/g, " ").trim();
    expect(text.length).toBeGreaterThan(200);
    expect(text).not.toMatch(
      /\b(API|JSON|LLM|geocod\w*|Nominatim|endpoint|in-memory)\b/i
    );
    const sentences = text.split(/[.!?]+\s/).filter((s) => s.trim());
    const words = text.split(/\s+/).length;
    expect(words / sentences.length).toBeLessThanOrEqual(20);
  });
});

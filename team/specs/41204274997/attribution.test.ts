import { createElement } from "react";
import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { CuriousApp } from "@/app/CuriousApp";

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

vi.mock("@/hooks/useTTS", () => ({
  useTTS: () => ({
    speak: vi.fn(),
    stop: vi.fn(),
    isSpeaking: false,
    autoRead: false,
    toggleAutoRead: vi.fn(),
    supported: true,
  }),
}));

const TEXT = /©\s*OpenStreetMap contributors/;

function setState(status: string, fact: string | null, error: string | null) {
  curious.state = { status, fact, error };
}

const renderApp = () => render(createElement(CuriousApp));

describe("OpenStreetMap attribution", () => {
  beforeEach(() => setState("idle", null, null));

  it("links to the OSM copyright page when a fact is shown", () => {
    setState("done", "A fun fact", null);
    renderApp();
    const link = screen.getByRole("link", { name: TEXT });
    expect(link).toHaveAttribute(
      "href",
      "https://www.openstreetmap.org/copyright"
    );
  });

  it("keeps the attribution while loading more", () => {
    setState("thinking", "A fun fact", null);
    renderApp();
    expect(screen.getByRole("link", { name: TEXT })).toBeInTheDocument();
  });

  it("shows no attribution when idle", () => {
    renderApp();
    expect(screen.queryByText(TEXT)).not.toBeInTheDocument();
  });

  it("shows no attribution on error without a fact", () => {
    setState("error", null, "Boom");
    renderApp();
    expect(screen.queryByText(TEXT)).not.toBeInTheDocument();
  });

  it("is visible without extra taps", () => {
    setState("done", "A fun fact", null);
    const { container } = renderApp();
    const link = screen.getByRole("link", { name: TEXT });
    expect(link.closest("details")).toBeNull();
    expect(link.closest("dialog")).toBeNull();
    expect(link.closest("[hidden]")).toBeNull();
    expect(link.closest("[aria-hidden='true']")).toBeNull();
    expect(link).toBeVisible();
    expect(container.querySelectorAll("a")).toHaveLength(1);
  });

  it("appears exactly once", () => {
    setState("done", "A fun fact", null);
    renderApp();
    expect(screen.getAllByText(TEXT)).toHaveLength(1);
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { CuriousApp } from "@/app/CuriousApp";

const TEXT = "© OpenStreetMap contributors";
const HREF = "https://www.openstreetmap.org/copyright";

function mockGeolocation() {
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: {
      getCurrentPosition: (ok: (p: unknown) => void) =>
        ok({ coords: { latitude: 51.5, longitude: -0.12 } }),
    },
  });
}

function mockFetch(ok: boolean) {
  let n = 0;
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => {
      n += 1;
      return {
        ok,
        json: async () =>
          ok ? { fact: `Fact number ${n}` } : { error: "Boom" },
      };
    })
  );
}

function findAttribution() {
  return screen.queryAllByRole("link", { name: TEXT });
}

async function clickCurious() {
  const button = screen.getAllByRole("button")[0];
  fireEvent.click(button);
}

describe("OpenStreetMap attribution", () => {
  beforeEach(() => {
    mockGeolocation();
    Object.defineProperty(window, "speechSynthesis", {
      configurable: true,
      value: undefined,
    });
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("is shown with the correct link next to a displayed fact", async () => {
    mockFetch(true);
    render(<CuriousApp />);
    await clickCurious();
    await screen.findByText("Fact number 1");

    const links = findAttribution();
    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute("href", HREF);
  });

  it("is visible without extra taps", async () => {
    mockFetch(true);
    render(<CuriousApp />);
    await clickCurious();
    await screen.findByText("Fact number 1");

    const [link] = findAttribution();
    expect(link).toBeDefined();
    expect(link.closest("details")).toBeNull();
    expect(link.closest("[hidden]")).toBeNull();
    expect(link.closest("[aria-hidden='true']")).toBeNull();
    expect(link).toBeVisible();
  });

  it("stays, once, after Tell me more", async () => {
    mockFetch(true);
    render(<CuriousApp />);
    await clickCurious();
    await screen.findByText("Fact number 1");

    const more = await screen.findByRole("button", { name: /more/i });
    fireEvent.click(more);
    await screen.findByText("Fact number 2");

    expect(findAttribution()).toHaveLength(1);
  });

  it("is not shown before any result", () => {
    mockFetch(true);
    render(<CuriousApp />);
    expect(findAttribution()).toHaveLength(0);
    expect(screen.queryByText(TEXT)).toBeNull();
  });

  it("is not shown when only an error is displayed", async () => {
    mockFetch(false);
    render(<CuriousApp />);
    await clickCurious();
    await screen.findByText("Boom");
    expect(findAttribution()).toHaveLength(0);
  });

  it("uses noopener when opening a new tab", async () => {
    mockFetch(true);
    render(<CuriousApp />);
    await clickCurious();
    await screen.findByText("Fact number 1");

    const [link] = findAttribution();
    expect(link).toBeDefined();
    if (link.getAttribute("target") === "_blank") {
      expect(link.getAttribute("rel") ?? "").toContain("noopener");
    }
  });
});

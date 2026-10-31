import { createElement } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CuriousApp } from "@/app/CuriousApp";

const ATTRIBUTION = "© OpenStreetMap contributors";
const COPYRIGHT_URL = "https://www.openstreetmap.org/copyright";

function mockGeolocation() {
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: {
      getCurrentPosition: (ok: PositionCallback) =>
        ok({
          coords: { latitude: 48.8584, longitude: 2.2945 },
        } as GeolocationPosition),
    },
  });
}

function mockFetch(responses: Array<{ ok: boolean; body: unknown }>) {
  const queue = [...responses];
  const fn = vi.fn(async () => {
    const next = queue.shift() ?? responses[responses.length - 1];
    return {
      ok: next.ok,
      status: next.ok ? 200 : 500,
      json: async () => next.body,
    } as Response;
  });
  vi.stubGlobal("fetch", fn);
}

const findLinks = () => screen.queryAllByRole("link", { name: ATTRIBUTION });
const renderApp = () => render(createElement(CuriousApp));

describe("OpenStreetMap attribution", () => {
  beforeEach(() => {
    mockGeolocation();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("is shown with the first fact, linking to the OSM copyright page", async () => {
    mockFetch([{ ok: true, body: { fact: "Fact one." } }]);
    const user = userEvent.setup();
    renderApp();
    expect(findLinks()).toHaveLength(0);

    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await screen.findByText("Fact one.");

    const links = findLinks();
    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute("href", COPYRIGHT_URL);
    expect(links[0].textContent).toBe(ATTRIBUTION);
  });

  it("is visible without extra taps", async () => {
    mockFetch([{ ok: true, body: { fact: "Fact one." } }]);
    const user = userEvent.setup();
    renderApp();
    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await screen.findByText("Fact one.");

    const link = findLinks()[0];
    expect(link).toBeDefined();
    expect(link).toBeVisible();
    expect(link.closest("details")).toBeNull();
    expect(link.closest("[hidden]")).toBeNull();
    expect(link.closest("[aria-hidden='true']")).toBeNull();
  });

  it("is still shown after Tell me more replaces the fact", async () => {
    mockFetch([
      { ok: true, body: { fact: "Fact one." } },
      { ok: true, body: { fact: "Fact two." } },
    ]);
    const user = userEvent.setup();
    renderApp();
    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await screen.findByText("Fact one.");
    await user.click(screen.getByRole("button", { name: /tell me more/i }));
    await screen.findByText("Fact two.");

    expect(findLinks()).toHaveLength(1);
    expect(findLinks()[0]).toHaveAttribute("href", COPYRIGHT_URL);
  });

  it("is not shown when the request failed and no fact is displayed", async () => {
    mockFetch([{ ok: false, body: { error: "Something went wrong." } }]);
    const user = userEvent.setup();
    renderApp();
    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await waitFor(() =>
      expect(screen.getByText("Something went wrong.")).toBeInTheDocument()
    );
    expect(findLinks()).toHaveLength(0);
  });
});

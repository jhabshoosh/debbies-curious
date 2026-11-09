import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { NextRequest } from "next/server";
import { CuriousApp } from "@/app/CuriousApp";
import { POST } from "@/app/api/curious/route";

const generateLocationFact = vi.fn();
let rateAllowed = true;

vi.mock("@/lib/llm/factory", () => ({
  createLLMProvider: () => ({ generateLocationFact }),
}));
vi.mock("@/lib/geocode", () => ({
  reverseGeocode: async () => ({}),
  formatLocationName: () => "Somewhere",
}));
vi.mock("@/lib/rate-limit", () => ({
  checkRateLimit: () => ({ allowed: rateAllowed }),
}));

const SECRET = "sk-secret-internal-key stack at /srv/app/provider.ts";

function apiRequest() {
  return new NextRequest("http://localhost/api/curious", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ latitude: 51.5, longitude: -0.12 }),
  });
}

async function callApi() {
  vi.spyOn(console, "error").mockImplementation(() => {});
  const res = await POST(apiRequest());
  const body = await res.json();
  return { status: res.status, error: String(body.error ?? "") };
}

describe("server error responses", () => {
  beforeEach(() => {
    generateLocationFact.mockReset();
    rateAllowed = true;
  });
  afterEach(() => vi.restoreAllMocks());

  it("reports an unexpected failure as 500 without leaking details", async () => {
    generateLocationFact.mockRejectedValue(new Error(SECRET));
    const { status, error } = await callApi();
    expect(status).toBe(500);
    expect(error.length).toBeGreaterThan(0);
    expect(error).not.toContain("sk-secret");
    expect(error).not.toContain("/srv/app");
  });

  it.each([429, 503, 529])(
    "reports story service status %i as 503, distinct from a glitch",
    async (providerStatus) => {
      generateLocationFact.mockRejectedValue(
        Object.assign(new Error(SECRET), { status: providerStatus })
      );
      const unavailable = await callApi();
      expect(unavailable.status).toBe(503);
      expect(unavailable.error).not.toContain("sk-secret");
      expect(unavailable.error).not.toContain("/srv/app");

      generateLocationFact.mockRejectedValue(new Error(SECRET));
      const glitch = await callApi();
      expect(unavailable.error).not.toBe(glitch.error);

      rateAllowed = false;
      const limited = await callApi();
      expect(limited.status).toBe(429);
      expect(unavailable.error).not.toBe(limited.error);
    }
  );
});

// ---- client ----

type GeoErr = { code: number } | null;

function mockGeolocation(failure: GeoErr) {
  const getCurrentPosition = (
    ok: (p: unknown) => void,
    fail: (e: unknown) => void
  ) => {
    if (failure) {
      fail({
        ...failure,
        PERMISSION_DENIED: 1,
        POSITION_UNAVAILABLE: 2,
        TIMEOUT: 3,
      });
    } else {
      ok({ coords: { latitude: 51.5, longitude: -0.12 } });
    }
  };
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: { getCurrentPosition },
  });
}

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function tapAndReadAlert() {
  const user = userEvent.setup();
  await user.click(screen.getByRole("button", { name: /i'm curious/i }));
  const alert = await screen.findByRole("alert");
  return alert.textContent ?? "";
}

const RETRY = /again|later|moment|retry/i;

describe("client error messages", () => {
  beforeEach(() => {
    mockGeolocation(null);
    vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("shows a friendly offline message instead of 'Failed to fetch'", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new TypeError("Failed to fetch"))
    );
    render(<CuriousApp />);
    const text = await tapAndReadAlert();
    expect(text).not.toMatch(/failed to fetch|typeerror/i);
    expect(text).toMatch(/internet|connection|network|online/i);
    expect(text).toMatch(RETRY);
  });

  it("does not show raw text when the server reply is not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          new Response("<html>Bad Gateway</html>", { status: 502 })
        )
    );
    render(<CuriousApp />);
    const text = await tapAndReadAlert();
    expect(text).not.toMatch(/unexpected token|json|<html|bad gateway/i);
    expect(text).toMatch(RETRY);
  });

  it("shows distinct, retry-friendly messages per failure kind", async () => {
    const texts: Record<string, string> = {};
    const scenarios: Record<string, () => void> = {
      offline: () =>
        vi
          .spyOn(globalThis, "fetch")
          .mockRejectedValue(new TypeError("Failed to fetch")),
      unavailable: () =>
        vi
          .spyOn(globalThis, "fetch")
          .mockResolvedValue(
            jsonResponse(503, { error: "upstream said no" })
          ),
      glitch: () =>
        vi
          .spyOn(globalThis, "fetch")
          .mockResolvedValue(jsonResponse(500, { error: "kaboom" })),
      rateLimit: () =>
        vi
          .spyOn(globalThis, "fetch")
          .mockResolvedValue(jsonResponse(429, { error: "slow down" })),
    };
    for (const [name, setup] of Object.entries(scenarios)) {
      vi.restoreAllMocks();
      vi.spyOn(console, "error").mockImplementation(() => {});
      setup();
      const { unmount } = render(<CuriousApp />);
      texts[name] = await tapAndReadAlert();
      unmount();
    }
    expect(new Set(Object.values(texts)).size).toBe(4);
    expect(texts.unavailable).not.toMatch(/upstream said no/);
    for (const t of Object.values(texts)) expect(t).toMatch(RETRY);
  });

  it("explains location denied with what to do", async () => {
    mockGeolocation({ code: 1 });
    vi.stubGlobal("fetch", vi.fn());
    render(<CuriousApp />);
    const text = await tapAndReadAlert();
    expect(text).toMatch(/denied|blocked|permission|allow/i);
    expect(text).toMatch(/settings|enable|allow/i);
  });

  it("explains location timeout and invites another try", async () => {
    mockGeolocation({ code: 3 });
    vi.stubGlobal("fetch", vi.fn());
    render(<CuriousApp />);
    const text = await tapAndReadAlert();
    expect(text).toMatch(/time/i);
    expect(text).toMatch(RETRY);
  });

  it("lets the user tap again after a failure without reloading", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(jsonResponse(200, { fact: "A lovely story." }));
    vi.stubGlobal("fetch", fetchMock);
    render(<CuriousApp />);
    await tapAndReadAlert();

    const retry = screen.getByRole("button", { name: /try again|curious/i });
    expect(retry).toBeEnabled();
    await userEvent.setup().click(retry);

    expect(await screen.findByText("A lovely story.")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("alert")).toBeNull());
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("keeps the first screen to the single button with no error", () => {
    vi.stubGlobal("fetch", vi.fn());
    render(<CuriousApp />);
    expect(
      screen.getByRole("button", { name: /i'm curious/i })
    ).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.queryByText(/try again/i)).toBeNull();
  });
});

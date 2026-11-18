import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { CuriousApp } from "@/app/CuriousApp";

const RAW =
  /failed to fetch|unexpected token|syntaxerror|typeerror|json|openai|anthropic|api key|upstream|undefined|null|econn|network ?error|\bstatus\b|\b50\d\b/i;
const NEXT_STEP = /try|again|check|later|settings|allow|enable|reload/i;

const GEO_CODES = {
  PERMISSION_DENIED: 1,
  POSITION_UNAVAILABLE: 2,
  TIMEOUT: 3,
};

function setGeo(impl: unknown) {
  Object.defineProperty(navigator, "geolocation", {
    value: impl,
    configurable: true,
  });
}

function geoOk() {
  setGeo({
    getCurrentPosition: (ok: (p: unknown) => void) =>
      ok({ coords: { latitude: 51.5, longitude: -0.12 } }),
  });
}

function geoFail(code: number) {
  setGeo({
    getCurrentPosition: (_ok: unknown, fail: (e: unknown) => void) =>
      fail({ code, message: "raw geo message", ...GEO_CODES }),
  });
}

function jsonRes(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  geoOk();
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  Reflect.deleteProperty(navigator, "geolocation");
});

async function tap(name: RegExp) {
  await act(async () => {
    fireEvent.click(screen.getByRole("button", { name }));
  });
}

async function expectFriendly() {
  const alert = await screen.findByRole("alert");
  const text = alert.textContent ?? "";
  expect(text.length).toBeGreaterThan(10);
  expect(text.length).toBeLessThan(200);
  expect(text).not.toMatch(RAW);
  expect(text).toMatch(NEXT_STEP);
}

describe("first screen", () => {
  it("shows one button and no alert", () => {
    render(<CuriousApp />);
    expect(screen.getByRole("button", { name: /i'm curious/i })).toBeVisible();
    expect(screen.queryByRole("alert")).toBeNull();
  });
});

describe("connection and service failures", () => {
  it("friendly message when the network is down", async () => {
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
  });

  it.each([500, 502, 503])(
    "friendly message for status %i with a technical body",
    async (status) => {
      fetchMock.mockResolvedValue(
        jsonRes({ error: "OpenAI API error: 401 Incorrect API key" }, status)
      );
      render(<CuriousApp />);
      await tap(/i'm curious/i);
      await expectFriendly();
    }
  );

  it("friendly message for an HTML error page", async () => {
    fetchMock.mockResolvedValue(
      new Response("<html>Bad Gateway</html>", { status: 502 })
    );
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
  });

  it("friendly message for a 200 that is not JSON", async () => {
    fetchMock.mockResolvedValue(new Response("<html>oops</html>"));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
  });

  it("friendly message for a 200 without a fact", async () => {
    fetchMock.mockResolvedValue(jsonRes({}));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
  });
});

describe("timeouts", () => {
  it("ends a hanging request with a retry message", async () => {
    vi.useFakeTimers();
    fetchMock.mockImplementation(
      (_url: string, init?: { signal?: AbortSignal }) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException("The operation was aborted.", "AbortError"))
          );
        })
    );
    render(<CuriousApp />);
    await tap(/i'm curious/i);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000);
    });
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByRole("button", { name: /please wait/i })).toBeDisabled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(55000);
    });
    await expectFriendly();
    expect(screen.getByRole("button", { name: /try again/i })).toBeEnabled();
  });
});

describe("location trouble", () => {
  it.each([
    ["permission denied", GEO_CODES.PERMISSION_DENIED],
    ["position unavailable", GEO_CODES.POSITION_UNAVAILABLE],
    ["timeout", GEO_CODES.TIMEOUT],
  ])("friendly message on %s", async (_label, code) => {
    geoFail(code);
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("friendly message when geolocation is unsupported", async () => {
    Reflect.deleteProperty(navigator, "geolocation");
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("friendly message when the geolocation call throws", async () => {
    setGeo({
      getCurrentPosition: () => {
        throw new Error("SecurityError: Only secure origins are allowed");
      },
    });
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
  });
});

describe("existing messages stay", () => {
  it("shows the daily-limit message", async () => {
    const msg =
      "Debbie's stories are resting for today. Please come back tomorrow!";
    fetchMock.mockResolvedValue(jsonRes({ error: msg }, 503));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    expect(await screen.findByRole("alert")).toHaveTextContent(msg);
  });

  it("shows the too-many-taps message", async () => {
    const msg = "Too many requests. Please wait a moment and try again.";
    fetchMock.mockResolvedValue(jsonRes({ error: msg }, 429));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    expect(await screen.findByRole("alert")).toHaveTextContent(msg);
  });
});

describe("retry", () => {
  it("one tap retries after a failure and shows the fact", async () => {
    fetchMock
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(jsonRes({ fact: "Big Ben is a bell." }));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await expectFriendly();
    await tap(/try again/i);
    expect(await screen.findByText("Big Ben is a bell.")).toBeVisible();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("failed Tell Me More is friendly and retryable in one tap", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonRes({ fact: "First fact." }))
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(jsonRes({ fact: "Second fact." }));
    render(<CuriousApp />);
    await tap(/i'm curious/i);
    await screen.findByText("First fact.");
    await tap(/tell me more/i);
    await expectFriendly();
    await tap(/try again/i);
    expect(await screen.findByText("Second fact.")).toBeVisible();
  });
});

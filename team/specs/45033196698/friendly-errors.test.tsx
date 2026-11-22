import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CuriousApp } from "@/app/CuriousApp";

const TECHNICAL =
  /TypeError|SyntaxError|NetworkError|JSON|Unexpected|failed to fetch|fetch|undefined|null|NaN|\bHTTP\b|\b[1-5]\d\d\b|<|>|stack|exception|Error:|ECONN|gateway/i;
const RETRY_HINT = /try|again|later|moment/i;

function mockGeolocation(mode: "ok" | "denied") {
  const getCurrentPosition = vi.fn(
    (
      ok: (p: GeolocationPosition) => void,
      fail: (e: GeolocationPositionError) => void
    ) => {
      if (mode === "ok") {
        ok({
          coords: { latitude: 51.5, longitude: -0.12 },
        } as GeolocationPosition);
      } else {
        fail({
          code: 1,
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3,
          message: "User denied Geolocation",
        } as GeolocationPositionError);
      }
    }
  );
  Object.defineProperty(navigator, "geolocation", {
    value: { getCurrentPosition },
    configurable: true,
  });
}

function setOnline(value: boolean) {
  Object.defineProperty(navigator, "onLine", {
    value,
    configurable: true,
  });
}

function htmlResponse(status: number) {
  return new Response("<html><body><h1>502 Bad Gateway</h1></body></html>", {
    status,
    headers: { "Content-Type": "text/html" },
  });
}

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function tap() {
  const user = userEvent.setup();
  render(<CuriousApp />);
  await user.click(screen.getByRole("button", { name: /i'm curious/i }));
  return user;
}

async function alertText() {
  const alert = await screen.findByRole("alert");
  return alert.textContent ?? "";
}

function expectFriendly(text: string) {
  expect(text.trim().length).toBeGreaterThan(10);
  expect(text).not.toMatch(TECHNICAL);
  expect(text).toMatch(RETRY_HINT);
}

function expectSingleRetry() {
  expect(screen.getAllByRole("button", { name: /try again/i })).toHaveLength(1);
}

describe("friendly tap failures", () => {
  beforeEach(() => {
    mockGeolocation("ok");
    setOnline(true);
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("explains a lost internet connection in plain words", async () => {
    setOnline(false);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new TypeError("Failed to fetch"))
    );
    await tap();
    const text = await alertText();
    expectFriendly(text);
    expect(text).toMatch(/internet|connection|online|offline/i);
    expectSingleRetry();
  });

  it("explains a flaky connection when the request itself fails", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new TypeError("NetworkError when attempting"))
    );
    await tap();
    const text = await alertText();
    expectFriendly(text);
    expect(text).toMatch(/internet|connection|network|signal/i);
    expectSingleRetry();
  });

  it("hides the parse error when the server returns an HTML gateway page", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(htmlResponse(502)));
    await tap();
    expectFriendly(await alertText());
    expectSingleRetry();
  });

  it("hides the parse error when a success status has an unreadable body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("<html>oops</html>", {
          status: 200,
          headers: { "Content-Type": "text/html" },
        })
      )
    );
    await tap();
    expectFriendly(await alertText());
    expectSingleRetry();
  });

  it("handles a story service that is down with a technical server message", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          jsonResponse(500, { error: "TypeError: OpenAI 401 invalid api key" })
        )
    );
    await tap();
    expectFriendly(await alertText());
    expectSingleRetry();
  });

  it("handles a service-down response with an empty error body", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(503, {})));
    await tap();
    expectFriendly(await alertText());
    expectSingleRetry();
  });

  it("still shows the daily-limit message clearly", async () => {
    const message =
      "Debbie's stories are resting for today. Please come back tomorrow!";
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(jsonResponse(503, { error: message }))
    );
    await tap();
    expect(await alertText()).toContain("resting for today");
    expectSingleRetry();
  });

  it("still shows the rate-limit message clearly", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          jsonResponse(429, {
            error: "Too many requests. Please wait a moment and try again.",
          })
        )
    );
    await tap();
    expect(await alertText()).toMatch(/too many requests/i);
    expectSingleRetry();
  });

  it("still explains denied location access", async () => {
    mockGeolocation("denied");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    await tap();
    const text = await alertText();
    expect(text).toMatch(/location/i);
    expect(text).toMatch(/denied|enable|allow|settings/i);
    expect(fetchMock).not.toHaveBeenCalled();
    expectSingleRetry();
  });

  it("recovers: retrying after a failure can succeed and clears the message", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(jsonResponse(200, { fact: "Big Ben is a bell." }));
    vi.stubGlobal("fetch", fetchMock);
    const user = await tap();
    await alertText();
    await user.click(screen.getByRole("button", { name: /try again/i }));
    expect(await screen.findByText("Big Ben is a bell.")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("is friendly when Tell me more fails after a first success", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(200, { fact: "Big Ben is a bell." }))
      .mockResolvedValueOnce(htmlResponse(502));
    vi.stubGlobal("fetch", fetchMock);
    const user = await tap();
    await screen.findByText("Big Ben is a bell.");
    await user.click(screen.getByRole("button", { name: /tell me more/i }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expectFriendly(await alertText());
  });

  it("successful tap is unchanged: shows the fact, no alert", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(jsonResponse(200, { fact: "Big Ben is a bell." }));
    vi.stubGlobal("fetch", fetchMock);
    await tap();
    expect(await screen.findByText("Big Ben is a bell.")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/curious");
    expect(init.method).toBe("POST");
    expect(JSON.parse(init.body)).toMatchObject({
      latitude: 51.5,
      longitude: -0.12,
    });
  });
});

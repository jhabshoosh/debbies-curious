import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { useGeolocation } from "@/hooks/useGeolocation";
import { useCurious } from "@/hooks/useCurious";

type Pos = { latitude: number; longitude: number };
const STALE: Pos = { latitude: 1, longitude: 1 };
const FRESH: Pos = { latitude: 2, longitude: 2 };

interface Opts {
  maximumAge?: number;
  timeout?: number;
}

function install(
  behaviour: (opts: Opts) => "fresh" | "stale" | "timeout" | "denied" | "none"
) {
  const calls: Opts[] = [];
  const err = (code: number) => ({
    code,
    PERMISSION_DENIED: 1,
    POSITION_UNAVAILABLE: 2,
    TIMEOUT: 3,
  });
  const geo = {
    getCurrentPosition: (
      ok: (p: unknown) => void,
      fail: (e: unknown) => void,
      opts: Opts = {}
    ) => {
      calls.push(opts);
      const r = behaviour(opts);
      const wrap = (c: Pos) => ({ coords: c });
      if (r === "fresh") ok(wrap(FRESH));
      else if (r === "stale") ok(wrap(STALE));
      else if (r === "denied") fail(err(1));
      else if (r === "none") fail(err(2));
      else setTimeout(() => fail(err(3)), opts.timeout ?? 0);
    },
  };
  Object.defineProperty(navigator, "geolocation", {
    value: geo,
    configurable: true,
  });
  return calls;
}

const isFreshReq = (o: Opts) => (o.maximumAge ?? 0) < 60000;

beforeEach(() => {
  vi.useRealTimers();
});
afterEach(() => {
  Reflect.deleteProperty(navigator, "geolocation");
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("fresh location", () => {
  it("returns the new position rather than a stale cached one", async () => {
    install((o) => (isFreshReq(o) ? "fresh" : "stale"));
    const { result } = renderHook(() => useGeolocation());
    let pos: Pos | undefined;
    await act(async () => {
      pos = await result.current.getPosition();
    });
    expect(pos).toEqual(FRESH);
  });

  it("falls back to a recent cached position when fresh fails", async () => {
    install((o) => (isFreshReq(o) ? "none" : "stale"));
    const { result } = renderHook(() => useGeolocation());
    let pos: Pos | undefined;
    await act(async () => {
      pos = await result.current.getPosition();
    });
    expect(pos).toEqual(STALE);
  });

  it("falls back after a bounded fresh timeout", async () => {
    vi.useFakeTimers();
    const calls = install((o) => (isFreshReq(o) ? "timeout" : "stale"));
    const { result } = renderHook(() => useGeolocation());
    let pos: Pos | undefined;
    const p = result.current.getPosition().then((v) => (pos = v));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10000);
      await p;
    });
    expect(calls[0].timeout).toBeLessThanOrEqual(10000);
    expect(pos).toEqual(STALE);
  });

  it("does not fall back when permission is denied", async () => {
    const calls = install(() => "denied");
    const { result } = renderHook(() => useGeolocation());
    await act(async () => {
      await expect(result.current.getPosition()).rejects.toThrow(/denied/i);
    });
    expect(calls).toHaveLength(1);
  });

  it("reports an error when no position is available at all", async () => {
    install(() => "none");
    const { result } = renderHook(() => useGeolocation());
    await act(async () => {
      await expect(result.current.getPosition()).rejects.toThrow(
        /unable to determine/i
      );
    });
  });

  it("never logs or stores location", async () => {
    install((o) => (isFreshReq(o) ? "fresh" : "stale"));
    const spies = (["log", "info", "warn", "error", "debug"] as const).map(
      (m) => vi.spyOn(console, m).mockImplementation(() => {})
    );
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    const { result } = renderHook(() => useGeolocation());
    await act(async () => {
      await result.current.getPosition();
    });
    for (const s of spies) expect(s).not.toHaveBeenCalled();
    expect(setItem).not.toHaveBeenCalled();
  });

  it("second tap after moving sends the new coordinates", async () => {
    let moved = false;
    install((o) => {
      if (!isFreshReq(o)) return "stale";
      return moved ? "fresh" : "none";
    });
    const bodies: { latitude: number }[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_u: string, init: { body: string }) => {
        bodies.push(JSON.parse(init.body));
        return { ok: true, json: async () => ({ fact: "f" }) };
      })
    );
    const { result } = renderHook(() => useCurious());
    await act(async () => {
      await result.current.askCurious();
    });
    moved = true;
    await act(async () => {
      await result.current.askCurious();
    });
    expect(bodies.map((b) => b.latitude)).toEqual([1, 2]);
  });
});

import { describe, it, expect, beforeEach, vi } from "vitest";
import { checkRateLimit, resetRateLimitStore } from "../rate-limit";

describe("checkRateLimit", () => {
  beforeEach(() => {
    resetRateLimitStore();
    vi.useRealTimers();
  });

  it("allows requests under the limit", () => {
    for (let i = 0; i < 10; i++) {
      expect(checkRateLimit("test-ip").allowed).toBe(true);
    }
  });

  it("blocks requests over the limit", () => {
    for (let i = 0; i < 10; i++) {
      checkRateLimit("test-ip");
    }
    expect(checkRateLimit("test-ip").allowed).toBe(false);
  });

  it("tracks different keys independently", () => {
    for (let i = 0; i < 10; i++) {
      checkRateLimit("ip-1");
    }
    expect(checkRateLimit("ip-1").allowed).toBe(false);
    expect(checkRateLimit("ip-2").allowed).toBe(true);
  });

  it("allows requests after window expires", () => {
    vi.useFakeTimers();

    for (let i = 0; i < 10; i++) {
      checkRateLimit("test-ip");
    }
    expect(checkRateLimit("test-ip").allowed).toBe(false);

    // Advance past the 1-minute window
    vi.advanceTimersByTime(61 * 1000);

    expect(checkRateLimit("test-ip").allowed).toBe(true);
  });
});

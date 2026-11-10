import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const generate = vi.fn();
const createProvider = vi.fn();

vi.mock("@/lib/llm/factory", () => ({
  createLLMProvider: (...a: unknown[]) => createProvider(...a),
}));
vi.mock("@/lib/geocode", () => ({
  reverseGeocode: vi.fn().mockResolvedValue({}),
  formatLocationName: vi.fn().mockReturnValue("Somewhere"),
}));

type Post = (r: Request) => Promise<Response>;

let ipCounter = 0;
async function call(post: Post, opts: { ip?: string; lat?: number } = {}) {
  const n = ipCounter++;
  const ip = opts.ip ?? `10.0.${Math.floor(n / 250)}.${n % 250}`;
  const req = new Request("http://localhost/api/curious", {
    method: "POST",
    headers: { "x-forwarded-for": ip, "content-type": "application/json" },
    body: JSON.stringify({ latitude: opts.lat ?? 10, longitude: 20 }),
  });
  const res = await post(req);
  return { status: res.status, body: await res.json() };
}

async function loadRoute(): Promise<Post> {
  vi.resetModules();
  const mod = await import("@/app/api/curious/route");
  return mod.POST as unknown as Post;
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-03-10T12:00:00Z"));
  generate.mockReset().mockResolvedValue("A fact");
  createProvider.mockReset().mockReturnValue({
    generateLocationFact: generate,
  });
  vi.spyOn(console, "error").mockImplementation(() => {});
  delete process.env.DAILY_REQUEST_LIMIT;
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  delete process.env.DAILY_REQUEST_LIMIT;
});

describe("daily story limit", () => {
  it("blocks after the configured limit, across IPs, without calling the AI", async () => {
    process.env.DAILY_REQUEST_LIMIT = "3";
    const post = await loadRoute();
    for (let i = 0; i < 3; i++) {
      const r = await call(post);
      expect(r.status).toBe(200);
      expect(r.body.fact).toBe("A fact");
    }
    createProvider.mockClear();
    generate.mockClear();
    const blocked = await call(post);
    expect(blocked.status).toBe(503);
    expect(generate).not.toHaveBeenCalled();
    expect(createProvider).not.toHaveBeenCalled();
  });

  it("uses a calm message that says stories are resting and to try tomorrow", async () => {
    process.env.DAILY_REQUEST_LIMIT = "1";
    const post = await loadRoute();
    await call(post);
    const { body } = await call(post);
    const msg = String(body.error).toLowerCase();
    expect(msg).toContain("rest");
    expect(msg).toContain("tomorrow");
    for (const bad of ["wrong", "error", "failed", "too many", "invalid"]) {
      expect(msg).not.toContain(bad);
    }
  });

  it("applies a sensible default limit when the variable is unset", async () => {
    const post = await loadRoute();
    let blockedAt = -1;
    for (let i = 0; i < 5001; i++) {
      const r = await call(post);
      if (r.status !== 200) {
        blockedAt = i;
        expect(r.status).toBe(503);
        break;
      }
    }
    expect(blockedAt).toBeGreaterThanOrEqual(50);
    expect(blockedAt).toBeLessThanOrEqual(5000);
  });

  it("resets the count on the next day", async () => {
    process.env.DAILY_REQUEST_LIMIT = "2";
    const post = await loadRoute();
    await call(post);
    await call(post);
    expect((await call(post)).status).toBe(503);
    vi.setSystemTime(new Date("2026-03-11T00:00:30Z"));
    expect((await call(post)).status).toBe(200);
  });

  it("does not spend budget on per-IP rate-limited or invalid requests", async () => {
    process.env.DAILY_REQUEST_LIMIT = "11";
    const post = await loadRoute();
    for (let i = 0; i < 10; i++) {
      expect((await call(post, { ip: "1.2.3.4" })).status).toBe(200);
    }
    for (let i = 0; i < 3; i++) {
      expect((await call(post, { ip: "1.2.3.4" })).status).toBe(429);
    }
    expect((await call(post, { lat: 999 })).status).toBe(400);
    expect((await call(post)).status).toBe(200);
    expect((await call(post)).status).toBe(503);
  });
});

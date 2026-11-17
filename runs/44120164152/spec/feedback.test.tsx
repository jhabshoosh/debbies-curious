import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { NextRequest } from "next/server";
import type { ReactNode } from "react";
import { CuriousApp } from "@/app/CuriousApp";
import PrivacyPage from "@/app/privacy/page";

vi.mock("next/link", () => ({
  default: ({ href, children }: { href: string; children: ReactNode }) => (
    <a href={href}>{children}</a>
  ),
}));

const load = (path: string) =>
  import(/* @vite-ignore */ path).catch(() => null);

type FeedbackBehaviour = "ok" | "pending" | "reject" | "500";

let feedbackBehaviour: FeedbackBehaviour;
let storyCount: number;
let fetchMock: ReturnType<typeof vi.fn>;

function feedbackCalls() {
  return fetchMock.mock.calls.filter(([url]) =>
    String(url).includes("/api/feedback")
  );
}

function feedbackBodies() {
  return feedbackCalls().map(([, init]) => JSON.parse(init.body as string));
}

beforeEach(() => {
  feedbackBehaviour = "ok";
  storyCount = 0;
  fetchMock = vi.fn(async (url: string) => {
    if (String(url).includes("/api/feedback")) {
      if (feedbackBehaviour === "pending") return new Promise(() => {});
      if (feedbackBehaviour === "reject") throw new TypeError("offline");
      if (feedbackBehaviour === "500") {
        return new Response("{}", { status: 500 });
      }
      return new Response("{}", { status: 200 });
    }
    storyCount += 1;
    return new Response(JSON.stringify({ fact: `Story number ${storyCount}` }), {
      status: 200,
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: {
      getCurrentPosition: (ok: (p: unknown) => void) =>
        ok({ coords: { latitude: 51.5007, longitude: -0.1246 } }),
    },
  });
  Object.defineProperty(window, "speechSynthesis", {
    configurable: true,
    value: { speak: vi.fn(), cancel: vi.fn() },
  });
  vi.stubGlobal(
    "SpeechSynthesisUtterance",
    class {
      text: string;
      constructor(text: string) {
        this.text = text;
      }
    }
  );
  localStorage.clear();
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  Reflect.deleteProperty(window, "speechSynthesis");
});

const up = () => screen.queryByRole("button", { name: /thumbs up/i });
const down = () => screen.queryByRole("button", { name: /thumbs down/i });

async function showFirstStory(user: ReturnType<typeof userEvent.setup>) {
  render(<CuriousApp />);
  await user.click(screen.getByRole("button", { name: /i'm curious/i }));
  await screen.findByText(/Story number 1/);
}

describe("thumbs control visibility", () => {
  it("first screen is one button with no thumbs control", () => {
    render(<CuriousApp />);
    expect(screen.getAllByRole("button")).toHaveLength(1);
    expect(up()).toBeNull();
    expect(down()).toBeNull();
  });

  it("appears below the story once a story is shown", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    const thumbsUp = up();
    expect(thumbsUp).not.toBeNull();
    expect(down()).not.toBeNull();
    expect(thumbsUp?.tagName).toBe("BUTTON");
    const story = screen.getByText(/Story number 1/);
    expect(
      story.compareDocumentPosition(thumbsUp as HTMLElement) &
        Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
  });

  it("is absent after an error", async () => {
    const user = userEvent.setup();
    fetchMock.mockImplementationOnce(
      async () => new Response(JSON.stringify({ error: "nope" }), { status: 500 })
    );
    render(<CuriousApp />);
    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await screen.findByText(/nope/);
    expect(up()).toBeNull();
    expect(down()).toBeNull();
  });
});

describe("voting", () => {
  it("sends only vote and kind, then thanks the user in a live region", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.click(up() as HTMLElement);

    expect(feedbackCalls()).toHaveLength(1);
    const [url, init] = feedbackCalls()[0];
    expect(String(url)).toContain("/api/feedback");
    expect(init.method).toBe("POST");
    expect(JSON.parse(init.body as string)).toEqual({
      vote: "up",
      kind: "first",
    });

    const thanks = await screen.findByText(/thank/i);
    expect(thanks.closest('[role="status"], [aria-live]')).not.toBeNull();
  });

  it("sends a down vote", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.click(down() as HTMLElement);
    expect(feedbackBodies()).toEqual([{ vote: "down", kind: "first" }]);
  });

  it("works from the keyboard", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    (up() as HTMLElement).focus();
    await user.keyboard("{Enter}");
    expect(feedbackBodies()).toEqual([{ vote: "up", kind: "first" }]);
  });

  it("marks a tell-me-more story as kind 'more', and a restart as 'first'", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.click(screen.getByRole("button", { name: /tell me more/i }));
    await screen.findByText(/Story number 2/);
    await user.click(down() as HTMLElement);
    expect(feedbackBodies()).toEqual([{ vote: "down", kind: "more" }]);

    await user.click(screen.getByRole("button", { name: /i'm curious/i }));
    await screen.findByText(/Story number 3/);
    await user.click(up() as HTMLElement);
    expect(feedbackBodies()).toEqual([
      { vote: "down", kind: "more" },
      { vote: "up", kind: "first" },
    ]);
  });

  it("cannot be sent twice for the same story", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.dblClick(up() as HTMLElement);
    for (const button of [up(), down(), up()]) {
      if (button) await user.click(button);
    }
    expect(feedbackCalls()).toHaveLength(1);
  });

  it("gives each new story a fresh control", async () => {
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.click(up() as HTMLElement);
    await screen.findByText(/thank/i);

    await user.click(screen.getByRole("button", { name: /tell me more/i }));
    await screen.findByText(/Story number 2/);
    expect(screen.queryByText(/thank/i)).toBeNull();
    expect(up()).toBeEnabled();
    expect(down()).toBeEnabled();

    await user.click(down() as HTMLElement);
    expect(feedbackCalls()).toHaveLength(2);
  });
});

describe("never gets in the way", () => {
  it("leaves every other control usable while a vote is pending", async () => {
    feedbackBehaviour = "pending";
    const user = userEvent.setup();
    await showFirstStory(user);
    await user.click(up() as HTMLElement);

    expect(screen.getByRole("button", { name: /i'm curious/i })).toBeEnabled();
    expect(screen.getByRole("button", { name: /tell me more/i })).toBeEnabled();
    const speak = vi.mocked(window.speechSynthesis.speak);
    speak.mockClear();
    await user.click(screen.getByRole("button", { name: /read aloud/i }));
    expect(speak).toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: /tell me more/i }));
    await screen.findByText(/Story number 2/);
  });

  it.each<FeedbackBehaviour>(["reject", "500"])(
    "shows nothing alarming when sending fails (%s)",
    async (behaviour) => {
      feedbackBehaviour = behaviour;
      const user = userEvent.setup();
      await showFirstStory(user);
      await user.click(up() as HTMLElement);
      await vi.waitFor(() => expect(feedbackCalls()).toHaveLength(1));

      expect(screen.queryByRole("alert")).toBeNull();
      expect(
        screen.queryByText(/error|fail|wrong|try again|couldn't|sorry/i)
      ).toBeNull();
      expect(screen.getByText(/Story number 1/)).toBeInTheDocument();
      const main = screen.getByRole("button", { name: /i'm curious/i });
      expect(main).toBeEnabled();
      expect(screen.queryByRole("button", { name: /try again/i })).toBeNull();
    }
  );
});

describe("POST /api/feedback", () => {
  const post = async (body: string, headers: Record<string, string> = {}) => {
    const mod = await load("@/app/api/feedback/route");
    expect(mod).not.toBeNull();
    const request = new NextRequest("http://localhost/api/feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...headers },
      body,
    });
    return (mod as { POST: (r: NextRequest) => Promise<Response> }).POST(
      request
    );
  };

  it.each([
    ["up", "first"],
    ["down", "more"],
  ])("accepts vote=%s kind=%s", async (vote, kind) => {
    const res = await post(JSON.stringify({ vote, kind }));
    expect(res.status).toBeGreaterThanOrEqual(200);
    expect(res.status).toBeLessThan(300);
  });

  it.each([
    ["bad vote", { vote: "sideways", kind: "first" }],
    ["missing vote", { kind: "first" }],
    ["bad kind", { vote: "up", kind: "third" }],
    ["missing kind", { vote: "up" }],
  ])("rejects %s with 400", async (_name, body) => {
    const res = await post(JSON.stringify(body));
    expect(res.status).toBe(400);
  });

  it("rejects a body that is not JSON with 400", async () => {
    const res = await post("not json{");
    expect(res.status).toBe(400);
  });

  it("never logs coordinates, places, story text or identifying data", async () => {
    const spies = (["log", "info", "warn", "error", "debug"] as const).map(
      (m) => vi.spyOn(console, m).mockImplementation(() => {})
    );
    await post(
      JSON.stringify({
        vote: "up",
        kind: "first",
        latitude: 48.85837,
        longitude: 2.294481,
        place: "Eiffel Tower Paris",
        fact: "SECRET-STORY-TEXT",
      }),
      {
        "x-forwarded-for": "203.0.113.77",
        "x-real-ip": "203.0.113.78",
        "user-agent": "SECRET-AGENT/9.9",
      }
    );
    const logged = JSON.stringify(spies.flatMap((s) => s.mock.calls));
    for (const secret of [
      "48.85837",
      "2.294481",
      "Eiffel",
      "SECRET-STORY-TEXT",
      "203.0.113.77",
      "203.0.113.78",
      "SECRET-AGENT",
    ]) {
      expect(logged).not.toContain(secret);
    }
  });
});

describe("privacy page", () => {
  it("says plainly what a vote does and doesn't record", () => {
    const { container } = render(<PrivacyPage />);
    const voteText = Array.from(container.querySelectorAll("p, li"))
      .map((el) => el.textContent ?? "")
      .filter((t) => /vote|thumbs/i.test(t))
      .join(" ");

    expect(voteText).not.toBe("");
    expect(voteText).toMatch(/\bup\b/i);
    expect(voteText).toMatch(/\bdown\b/i);
    expect(voteText).toMatch(/time|date|hour|day/i);
    expect(voteText).toMatch(/tell me more/i);
    expect(voteText).toMatch(/location/i);
    expect(voteText).toMatch(/story|stories/i);
    expect(voteText).toMatch(/\b(not|never|no)\b/i);
    expect(voteText).toMatch(/who you are|identif|you\b/i);
    expect(within(container).getByRole("link", { name: /back/i })).toBeTruthy();
  });
});

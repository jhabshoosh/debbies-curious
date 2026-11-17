import { NextRequest, NextResponse } from "next/server";

const VOTES = ["up", "down"];
const KINDS = ["first", "more"];
const HOUR_MS = 60 * 60 * 1000;

export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  const { vote, kind } = (body && typeof body === "object" ? body : {}) as {
    vote?: unknown;
    kind?: unknown;
  };

  if (
    typeof vote !== "string" ||
    typeof kind !== "string" ||
    !VOTES.includes(vote) ||
    !KINDS.includes(kind)
  ) {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Only the choice, the kind of story and a timestamp rounded to the hour.
  const hour = new Date(Math.floor(Date.now() / HOUR_MS) * HOUR_MS);
  console.log(JSON.stringify({ event: "vote", vote, kind, hour }));

  return NextResponse.json({ ok: true });
}

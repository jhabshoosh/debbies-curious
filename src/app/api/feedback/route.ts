import { NextRequest, NextResponse } from "next/server";

const VOTES = ["up", "down"];
const KINDS = ["first", "more"];

export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  const { vote, kind } = (body ?? {}) as { vote?: unknown; kind?: unknown };
  if (
    typeof vote !== "string" ||
    typeof kind !== "string" ||
    !VOTES.includes(vote) ||
    !KINDS.includes(kind)
  ) {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Coarse timestamp: the day only. Nothing else from the request is logged.
  const day = new Date().toISOString().slice(0, 10);
  console.log(JSON.stringify({ event: "feedback", vote, kind, day }));

  return NextResponse.json({ ok: true });
}

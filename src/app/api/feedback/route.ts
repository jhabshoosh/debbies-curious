import { NextRequest, NextResponse } from "next/server";

const HOUR_MS = 60 * 60 * 1000;

export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON." }, { status: 400 });
  }

  const { vote, kind } = (body ?? {}) as { vote?: unknown; kind?: unknown };
  if (vote !== "up" && vote !== "down") {
    return NextResponse.json({ error: "Invalid vote." }, { status: 400 });
  }
  if (kind !== "first" && kind !== "more") {
    return NextResponse.json({ error: "Invalid kind." }, { status: 400 });
  }

  // Only the choice, the kind and the hour are recorded. Nothing else.
  const hour = new Date(Math.floor(Date.now() / HOUR_MS) * HOUR_MS);
  console.log(JSON.stringify({ feedback: { vote, kind, hour } }));

  return NextResponse.json({ ok: true });
}

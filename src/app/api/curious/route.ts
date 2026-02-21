import { NextRequest, NextResponse } from "next/server";
import { createLLMProvider } from "@/lib/llm/factory";
import { checkRateLimit } from "@/lib/rate-limit";
import type {
  CuriousRequest,
  CuriousResponse,
  CuriousErrorResponse,
} from "@/types/api";

function getClientIP(request: NextRequest): string {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "unknown"
  );
}

function isValidCoordinates(lat: number, lng: number): boolean {
  return (
    typeof lat === "number" &&
    typeof lng === "number" &&
    !isNaN(lat) &&
    !isNaN(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

export async function POST(request: NextRequest) {
  try {
    const body = (await request.json()) as CuriousRequest;
    const { latitude, longitude, previousFacts } = body;

    if (!isValidCoordinates(latitude, longitude)) {
      return NextResponse.json<CuriousErrorResponse>(
        {
          error:
            "Invalid coordinates. Latitude must be -90 to 90, longitude -180 to 180.",
        },
        { status: 400 }
      );
    }

    const ip = getClientIP(request);
    const { allowed } = checkRateLimit(ip);
    if (!allowed) {
      return NextResponse.json<CuriousErrorResponse>(
        { error: "Too many requests. Please wait a moment and try again." },
        { status: 429 }
      );
    }

    const provider = createLLMProvider();
    const fact = await provider.generateLocationFact(
      latitude,
      longitude,
      previousFacts
    );

    return NextResponse.json<CuriousResponse>({ fact });
  } catch (error) {
    console.error("Error in /api/curious:", error);
    return NextResponse.json<CuriousErrorResponse>(
      { error: "Something went wrong. Please try again." },
      { status: 500 }
    );
  }
}

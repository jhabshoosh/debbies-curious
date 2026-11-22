"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

const FRIENDLY_FALLBACK =
  "Debbie's story service is having a hiccup. Please try again in a moment.";

interface CuriousState {
  status: CuriousStatus;
  fact: string | null;
  error: string | null;
}

export function useCurious() {
  const [state, setState] = useState<CuriousState>({
    status: "idle",
    fact: null,
    error: null,
  });

  const { getPosition } = useGeolocation();
  const previousFactsRef = useRef<string[]>([]);
  const lastCoordsRef = useRef<{
    latitude: number;
    longitude: number;
  } | null>(null);

  const fetchFact = useCallback(
    async (latitude: number, longitude: number, previousFacts: string[]) => {
      setState((prev) => ({ ...prev, status: "thinking" }));

      const fail = (error: string) =>
        setState({ status: "error", fact: null, error });

      let response: Response;
      try {
        response = await fetch("/api/curious", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ latitude, longitude, previousFacts }),
        });
      } catch {
        fail(
          typeof navigator !== "undefined" && navigator.onLine === false
            ? "You seem to be offline. Check your internet connection and try again."
            : "We couldn't reach Debbie. Check your connection and try again."
        );
        return;
      }

      let body: Partial<CuriousResponse & CuriousErrorResponse> | null = null;
      try {
        body = await response.json();
      } catch {
        body = null;
      }

      if (!response.ok) {
        // Only the server's own limit messages are meant for people to read.
        const serverMessage =
          (response.status === 429 || response.status === 503) &&
          typeof body?.error === "string" &&
          body.error.trim()
            ? body.error
            : null;
        fail(serverMessage ?? FRIENDLY_FALLBACK);
        return;
      }

      if (typeof body?.fact !== "string" || !body.fact) {
        fail(FRIENDLY_FALLBACK);
        return;
      }

      previousFactsRef.current = [...previousFacts, body.fact];
      setState({ status: "done", fact: body.fact, error: null });
    },
    []
  );

  const askCurious = useCallback(async () => {
    setState({ status: "locating", fact: null, error: null });
    previousFactsRef.current = [];

    try {
      const position = await getPosition();
      lastCoordsRef.current = position;
      await fetchFact(position.latitude, position.longitude, []);
    } catch (err) {
      setState({
        status: "error",
        fact: null,
        error:
          err instanceof Error ? err.message : "Could not get your location.",
      });
    }
  }, [getPosition, fetchFact]);

  const tellMeMore = useCallback(async () => {
    if (!lastCoordsRef.current) return;
    const { latitude, longitude } = lastCoordsRef.current;
    await fetchFact(latitude, longitude, previousFactsRef.current);
  }, [fetchFact]);

  return { ...state, askCurious, tellMeMore };
}

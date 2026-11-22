"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

interface CuriousState {
  status: CuriousStatus;
  fact: string | null;
  error: string | null;
}

const GENERIC_FAILURE_MESSAGE =
  "Debbie is having a little trouble right now. Please try again in a moment.";

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

      let response: Response;
      try {
        response = await fetch("/api/curious", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ latitude, longitude, previousFacts }),
        });
      } catch {
        const offline = typeof navigator !== "undefined" && !navigator.onLine;
        setState({
          status: "error",
          fact: null,
          error: offline
            ? "You seem to be offline. Check your internet connection and try again."
            : "We couldn't reach Debbie. Check your connection and try again in a moment.",
        });
        return;
      }

      let body: unknown = null;
      try {
        body = await response.json();
      } catch {
        body = null;
      }

      if (!response.ok) {
        const message =
          body && typeof (body as CuriousErrorResponse).error === "string"
            ? (body as CuriousErrorResponse).error
            : "";
        const showServerMessage =
          response.status === 429 || /resting for today/i.test(message);
        setState({
          status: "error",
          fact: null,
          error:
            showServerMessage && message ? message : GENERIC_FAILURE_MESSAGE,
        });
        return;
      }

      const fact = body ? (body as CuriousResponse).fact : null;
      if (typeof fact !== "string" || !fact) {
        setState({
          status: "error",
          fact: null,
          error: GENERIC_FAILURE_MESSAGE,
        });
        return;
      }

      previousFactsRef.current = [...previousFacts, fact];
      setState({ status: "done", fact, error: null });
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

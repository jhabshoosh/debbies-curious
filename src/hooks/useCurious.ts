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

const OFFLINE_MESSAGE =
  "You seem to be offline. Check your internet connection and try again.";
const NETWORK_MESSAGE =
  "We couldn't reach Debbie. Check your connection and try again in a moment.";
const GENERIC_MESSAGE =
  "Debbie's having a hard time finding a story right now. Please try again in a moment.";

// Server messages written for users; anything else may be technical.
function isUserFacingMessage(message: string): boolean {
  return (
    /^Too many requests\./.test(message) || /resting for today/.test(message)
  );
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
            ? OFFLINE_MESSAGE
            : NETWORK_MESSAGE
        );
        return;
      }

      let body: unknown = null;
      try {
        body = await response.json();
      } catch {
        // Unreadable body: handled below.
      }

      if (!response.ok) {
        const serverMessage = (body as Partial<CuriousErrorResponse> | null)
          ?.error;
        fail(
          typeof serverMessage === "string" &&
            isUserFacingMessage(serverMessage)
            ? serverMessage
            : GENERIC_MESSAGE
        );
        return;
      }

      const fact = (body as Partial<CuriousResponse> | null)?.fact;
      if (typeof fact !== "string" || !fact) {
        fail(GENERIC_MESSAGE);
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

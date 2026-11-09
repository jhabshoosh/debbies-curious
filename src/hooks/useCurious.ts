"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse } from "@/types/api";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

interface CuriousState {
  status: CuriousStatus;
  fact: string | null;
  error: string | null;
}

class HttpError extends Error {
  constructor(public status: number) {
    super(`HTTP ${status}`);
  }
}

function friendlyMessage(err: unknown): string {
  if (err instanceof HttpError) {
    if (err.status === 429) {
      return "You're asking a lot! Please wait a moment and try again.";
    }
    if (err.status === 503) {
      return "The story service is busy right now. Please try again later.";
    }
    return "Something went wrong on our end. Please try again.";
  }
  if (err instanceof TypeError) {
    return "We couldn't reach the server. Check your internet connection and try again.";
  }
  return "Something went wrong. Please try again.";
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

      try {
        const response = await fetch("/api/curious", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ latitude, longitude, previousFacts }),
        });

        if (!response.ok) {
          throw new HttpError(response.status);
        }

        const data: CuriousResponse = await response.json();
        previousFactsRef.current = [...previousFacts, data.fact];
        setState({ status: "done", fact: data.fact, error: null });
      } catch (err) {
        setState({
          status: "error",
          fact: null,
          error: friendlyMessage(err),
        });
      }
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

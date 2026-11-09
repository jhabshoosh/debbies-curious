"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse } from "@/types/api";

const OFFLINE_MESSAGE =
  "We can't reach the internet. Check your connection and try again.";
const UNAVAILABLE_MESSAGE =
  "Our storyteller is busy right now. Please try again in a little while.";
const RATE_LIMIT_MESSAGE =
  "Too many taps too quickly. Please wait a moment and try again.";
const GENERIC_MESSAGE = "Something went wrong on our end. Please try again.";

function messageForStatus(status: number): string {
  if (status === 429) return RATE_LIMIT_MESSAGE;
  if (status === 503) return UNAVAILABLE_MESSAGE;
  return GENERIC_MESSAGE;
}

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

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

      try {
        let response: Response;
        try {
          response = await fetch("/api/curious", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ latitude, longitude, previousFacts }),
          });
        } catch {
          throw new Error(OFFLINE_MESSAGE);
        }

        if (!response.ok) {
          throw new Error(messageForStatus(response.status));
        }

        let data: CuriousResponse;
        try {
          data = await response.json();
        } catch {
          throw new Error(GENERIC_MESSAGE);
        }
        previousFactsRef.current = [...previousFacts, data.fact];
        setState({ status: "done", fact: data.fact, error: null });
      } catch (err) {
        setState({
          status: "error",
          fact: null,
          error: err instanceof Error ? err.message : GENERIC_MESSAGE,
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

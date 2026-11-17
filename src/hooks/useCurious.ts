"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

export type StoryKind = "first" | "more";

interface CuriousState {
  status: CuriousStatus;
  fact: string | null;
  error: string | null;
  storyId: number;
  kind: StoryKind;
}

export function useCurious() {
  const [state, setState] = useState<CuriousState>({
    status: "idle",
    fact: null,
    error: null,
    storyId: 0,
    kind: "first",
  });
  const storyCountRef = useRef(0);

  const { getPosition } = useGeolocation();
  const previousFactsRef = useRef<string[]>([]);
  const lastCoordsRef = useRef<{
    latitude: number;
    longitude: number;
  } | null>(null);

  const fetchFact = useCallback(
    async (
      latitude: number,
      longitude: number,
      previousFacts: string[],
      kind: StoryKind
    ) => {
      setState((prev) => ({ ...prev, status: "thinking" }));

      try {
        const response = await fetch("/api/curious", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ latitude, longitude, previousFacts }),
        });

        if (!response.ok) {
          const errorData: CuriousErrorResponse = await response.json();
          throw new Error(errorData.error || "Something went wrong.");
        }

        const data: CuriousResponse = await response.json();
        previousFactsRef.current = [...previousFacts, data.fact];
        storyCountRef.current += 1;
        setState({
          status: "done",
          fact: data.fact,
          error: null,
          storyId: storyCountRef.current,
          kind,
        });
      } catch (err) {
        setState((prev) => ({
          ...prev,
          status: "error",
          fact: null,
          error: err instanceof Error ? err.message : "Something went wrong.",
        }));
      }
    },
    []
  );

  const askCurious = useCallback(async () => {
    setState((prev) => ({
      ...prev,
      status: "locating",
      fact: null,
      error: null,
    }));
    previousFactsRef.current = [];

    try {
      const position = await getPosition();
      lastCoordsRef.current = position;
      await fetchFact(position.latitude, position.longitude, [], "first");
    } catch (err) {
      setState((prev) => ({
        ...prev,
        status: "error",
        fact: null,
        error:
          err instanceof Error ? err.message : "Could not get your location.",
      }));
    }
  }, [getPosition, fetchFact]);

  const tellMeMore = useCallback(async () => {
    if (!lastCoordsRef.current) return;
    const { latitude, longitude } = lastCoordsRef.current;
    await fetchFact(latitude, longitude, previousFactsRef.current, "more");
  }, [fetchFact]);

  return { ...state, askCurious, tellMeMore };
}

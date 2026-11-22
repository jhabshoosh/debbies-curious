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
  "You seem to be offline. Please check your internet connection and try again.";
const NETWORK_MESSAGE =
  "We couldn't reach Debbie. Please check your connection and try again.";
const SERVICE_MESSAGE =
  "Debbie's story service is taking a short break. Please try again in a moment.";

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
          error: offline ? OFFLINE_MESSAGE : NETWORK_MESSAGE,
        });
        return;
      }

      let body: Partial<CuriousResponse & CuriousErrorResponse> | null = null;
      try {
        body = await response.json();
      } catch {
        body = null;
      }

      if (!response.ok) {
        const serverMessage = body?.error;
        const showServerMessage =
          typeof serverMessage === "string" &&
          (response.status === 429 || serverMessage.includes("resting for today"));
        setState({
          status: "error",
          fact: null,
          error: showServerMessage ? serverMessage : SERVICE_MESSAGE,
        });
        return;
      }

      if (!body || typeof body.fact !== "string" || !body.fact) {
        setState({ status: "error", fact: null, error: SERVICE_MESSAGE });
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

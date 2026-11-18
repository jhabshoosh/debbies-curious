"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation, FriendlyError } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

const REQUEST_TIMEOUT_MS = 60000;
const DAILY_LIMIT_MESSAGE =
  "Debbie's stories are resting for today. Please come back tomorrow!";
const RATE_LIMIT_MESSAGE =
  "Too many requests. Please wait a moment and try again.";
const SERVICE_MESSAGE =
  "Debbie couldn't come up with a story just now. Please try again in a moment.";
const CONNECTION_MESSAGE =
  "Couldn't reach Debbie. Check your internet connection and try again.";
const TIMEOUT_MESSAGE = "That took too long. Please try again.";
const LOCATION_MESSAGE =
  "We couldn't find your location. Please check your location settings and try again.";

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

      const controller = new AbortController();
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        controller.abort();
      }, REQUEST_TIMEOUT_MS);

      try {
        const response = await fetch("/api/curious", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ latitude, longitude, previousFacts }),
          signal: controller.signal,
        });

        if (!response.ok) {
          let serverMessage: unknown;
          try {
            const errorData: CuriousErrorResponse = await response.json();
            serverMessage = errorData?.error;
          } catch {
            serverMessage = undefined;
          }
          const known =
            (response.status === 503 &&
              serverMessage === DAILY_LIMIT_MESSAGE) ||
            (response.status === 429 && serverMessage === RATE_LIMIT_MESSAGE);
          throw new FriendlyError(
            known ? (serverMessage as string) : SERVICE_MESSAGE
          );
        }

        let data: CuriousResponse | null;
        try {
          data = await response.json();
        } catch {
          throw new FriendlyError(SERVICE_MESSAGE);
        }
        const fact = data?.fact;
        if (typeof fact !== "string" || !fact.trim()) {
          throw new FriendlyError(SERVICE_MESSAGE);
        }
        previousFactsRef.current = [...previousFacts, fact];
        setState({ status: "done", fact, error: null });
      } catch (err) {
        let error = CONNECTION_MESSAGE;
        if (err instanceof FriendlyError) error = err.message;
        else if (timedOut) error = TIMEOUT_MESSAGE;
        setState({ status: "error", fact: null, error });
      } finally {
        clearTimeout(timer);
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
          err instanceof FriendlyError ? err.message : LOCATION_MESSAGE,
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

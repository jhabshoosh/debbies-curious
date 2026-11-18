"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import { FriendlyError } from "./friendly-error";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

const REQUEST_TIMEOUT_MS = 60000;

const SERVICE_MESSAGE =
  "Debbie's storyteller is having trouble right now. Please try again in a moment.";
const NETWORK_MESSAGE =
  "We couldn't reach the story service. Check your connection and try again.";
const TIMEOUT_MESSAGE = "That took too long. Please try again.";
const LOCATION_MESSAGE =
  "We couldn't get your location. Please check your location settings and try again.";

const KNOWN_SERVER_MESSAGES = [
  "Debbie's stories are resting for today. Please come back tomorrow!",
  "Too many requests. Please wait a moment and try again.",
];

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
          throw new FriendlyError(
            typeof serverMessage === "string" &&
            KNOWN_SERVER_MESSAGES.includes(serverMessage)
              ? serverMessage
              : SERVICE_MESSAGE
          );
        }

        let data: CuriousResponse | null = null;
        try {
          data = await response.json();
        } catch {
          data = null;
        }
        if (!data || typeof data.fact !== "string" || !data.fact.trim()) {
          throw new FriendlyError(SERVICE_MESSAGE);
        }
        previousFactsRef.current = [...previousFacts, data.fact];
        setState({ status: "done", fact: data.fact, error: null });
      } catch (err) {
        let error = NETWORK_MESSAGE;
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
        error: err instanceof FriendlyError ? err.message : LOCATION_MESSAGE,
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

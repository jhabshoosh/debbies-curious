"use client";

import { useState, useCallback, useRef } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

const REQUEST_TIMEOUT_MS = 60000;

const KNOWN_SERVER_MESSAGES = [
  "Debbie's stories are resting for today. Please come back tomorrow!",
  "Too many requests. Please wait a moment and try again.",
];

const MESSAGES = {
  network:
    "We couldn't reach Debbie. Please check your connection and try again.",
  service: "Debbie's story got lost on the way. Please try again in a moment.",
  timeout: "That took too long. Please try again.",
  location:
    "We couldn't find your location. Please check your settings and try again.",
};

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
      const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      const fail = (error: string) =>
        setState({ status: "error", fact: null, error });

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
          fail(
            typeof serverMessage === "string" &&
              KNOWN_SERVER_MESSAGES.includes(serverMessage)
              ? serverMessage
              : MESSAGES.service
          );
          return;
        }

        let data: Partial<CuriousResponse> | null = null;
        try {
          data = await response.json();
        } catch {
          data = null;
        }
        if (!data || typeof data.fact !== "string" || !data.fact.trim()) {
          fail(MESSAGES.service);
          return;
        }
        previousFactsRef.current = [...previousFacts, data.fact];
        setState({ status: "done", fact: data.fact, error: null });
      } catch {
        fail(controller.signal.aborted ? MESSAGES.timeout : MESSAGES.network);
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
          err instanceof Error && err.message
            ? err.message
            : MESSAGES.location,
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

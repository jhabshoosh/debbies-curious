"use client";

import { useState, useCallback } from "react";
import { useGeolocation } from "./useGeolocation";
import type { CuriousResponse, CuriousErrorResponse } from "@/types/api";

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

  const askCurious = useCallback(async () => {
    setState({ status: "locating", fact: null, error: null });

    let latitude: number;
    let longitude: number;

    try {
      const position = await getPosition();
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (err) {
      setState({
        status: "error",
        fact: null,
        error:
          err instanceof Error ? err.message : "Could not get your location.",
      });
      return;
    }

    setState((prev) => ({ ...prev, status: "thinking" }));

    try {
      const response = await fetch("/api/curious", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ latitude, longitude }),
      });

      if (!response.ok) {
        const errorData: CuriousErrorResponse = await response.json();
        throw new Error(errorData.error || "Something went wrong.");
      }

      const data: CuriousResponse = await response.json();
      setState({ status: "done", fact: data.fact, error: null });
    } catch (err) {
      setState({
        status: "error",
        fact: null,
        error: err instanceof Error ? err.message : "Something went wrong.",
      });
    }
  }, [getPosition]);

  return { ...state, askCurious };
}

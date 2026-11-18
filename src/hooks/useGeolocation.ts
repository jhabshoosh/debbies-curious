"use client";

import { useState, useCallback } from "react";

interface GeolocationState {
  latitude: number | null;
  longitude: number | null;
  error: string | null;
  loading: boolean;
}

export function useGeolocation() {
  const [state, setState] = useState<GeolocationState>({
    latitude: null,
    longitude: null,
    error: null,
    loading: false,
  });

  const getPosition = useCallback((): Promise<{
    latitude: number;
    longitude: number;
  }> => {
    return new Promise((resolve, reject) => {
      const fail = (error: string) => {
        setState((prev) => ({ ...prev, error, loading: false }));
        reject(new Error(error));
      };

      if (!navigator.geolocation) {
        fail(
          "Location isn't available on this device. Please check your browser settings and try again."
        );
        return;
      }

      setState((prev) => ({ ...prev, loading: true, error: null }));

      const onSuccess = (position: GeolocationPosition) => {
        const { latitude, longitude } = position.coords;
        setState({ latitude, longitude, error: null, loading: false });
        resolve({ latitude, longitude });
      };

      const onFailure = (err: GeolocationPositionError) => {
        let error: string;
        switch (err.code) {
          case err.PERMISSION_DENIED:
            error =
              "Location access was denied. Please enable location in your browser settings.";
            break;
          case err.POSITION_UNAVAILABLE:
            error = "Unable to determine your location. Please try again.";
            break;
          case err.TIMEOUT:
            error = "Location request timed out. Please try again.";
            break;
          default:
            error =
              "We couldn't find your location. Please try again in a moment.";
        }
        fail(error);
      };

      // Ask for a fresh fix first; fall back to a recent cached one.
      try {
        navigator.geolocation.getCurrentPosition(
          onSuccess,
          (err) => {
            if (err.code === err.PERMISSION_DENIED) {
              onFailure(err);
              return;
            }
            try {
              navigator.geolocation.getCurrentPosition(onSuccess, onFailure, {
                enableHighAccuracy: false,
                timeout: 10000,
                maximumAge: 300000, // 5 minutes
              });
            } catch {
              fail(
                "We couldn't find your location. Please check your settings and try again."
              );
            }
          },
          {
            enableHighAccuracy: false,
            timeout: 8000,
            maximumAge: 0,
          }
        );
      } catch {
        fail(
          "We couldn't find your location. Please check your settings and try again."
        );
      }
    });
  }, []);

  return { ...state, getPosition };
}

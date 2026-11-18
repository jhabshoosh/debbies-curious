"use client";

import { useState, useCallback } from "react";
import { FriendlyError } from "./friendly-error";

interface GeolocationState {
  latitude: number | null;
  longitude: number | null;
  error: string | null;
  loading: boolean;
}

const GENERIC_LOCATION_ERROR =
  "We couldn't get your location. Please check your location settings and try again.";

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
        reject(new FriendlyError(error));
      };

      if (!navigator.geolocation) {
        fail(
          "Location isn't available on this device. Please try again on a device or browser that supports it."
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
        switch (err.code) {
          case err.PERMISSION_DENIED:
            fail(
              "Location access was denied. Please enable location in your browser settings."
            );
            break;
          case err.POSITION_UNAVAILABLE:
            fail("Unable to determine your location. Please try again.");
            break;
          case err.TIMEOUT:
            fail("Location request timed out. Please try again.");
            break;
          default:
            fail(GENERIC_LOCATION_ERROR);
        }
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
              fail(GENERIC_LOCATION_ERROR);
            }
          },
          {
            enableHighAccuracy: false,
            timeout: 8000,
            maximumAge: 0,
          }
        );
      } catch {
        fail(GENERIC_LOCATION_ERROR);
      }
    });
  }, []);

  return { ...state, getPosition };
}

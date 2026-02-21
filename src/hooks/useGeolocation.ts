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
      if (!navigator.geolocation) {
        const error = "Location services are not available on this device.";
        setState((prev) => ({ ...prev, error, loading: false }));
        reject(new Error(error));
        return;
      }

      setState((prev) => ({ ...prev, loading: true, error: null }));

      navigator.geolocation.getCurrentPosition(
        (position) => {
          const { latitude, longitude } = position.coords;
          setState({ latitude, longitude, error: null, loading: false });
          resolve({ latitude, longitude });
        },
        (err) => {
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
              error = "An unexpected error occurred getting your location.";
          }
          setState((prev) => ({ ...prev, error, loading: false }));
          reject(new Error(error));
        },
        {
          enableHighAccuracy: false,
          timeout: 10000,
          maximumAge: 300000, // 5 minutes
        }
      );
    });
  }, []);

  return { ...state, getPosition };
}

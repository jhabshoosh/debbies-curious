"use client";

import { useState, useCallback, useSyncExternalStore, useRef } from "react";

const TTS_AUTO_KEY = "debbies-curious-tts-auto";

function getAutoReadPreference(): boolean {
  if (typeof window === "undefined") return true;
  const stored = localStorage.getItem(TTS_AUTO_KEY);
  return stored === null ? true : stored === "true";
}

function getSupported(): boolean {
  if (typeof window === "undefined") return true;
  return "speechSynthesis" in window;
}

function subscribe() {
  // No external store to subscribe to — values are static after hydration
  return () => {};
}

export function useTTS() {
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [autoRead, setAutoRead] = useState(getAutoReadPreference);
  const supported = useSyncExternalStore(subscribe, getSupported, () => true);
  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);

  const speak = useCallback(
    (text: string) => {
      if (!supported) return;

      // Cancel any ongoing speech
      window.speechSynthesis.cancel();

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.rate = 0.95;
      utterance.pitch = 1;

      utterance.onstart = () => setIsSpeaking(true);
      utterance.onend = () => setIsSpeaking(false);
      utterance.onerror = () => setIsSpeaking(false);

      utteranceRef.current = utterance;
      window.speechSynthesis.speak(utterance);
    },
    [supported]
  );

  const stop = useCallback(() => {
    if (!supported) return;
    window.speechSynthesis.cancel();
    setIsSpeaking(false);
  }, [supported]);

  const toggleAutoRead = useCallback(() => {
    setAutoRead((prev) => {
      const next = !prev;
      localStorage.setItem(TTS_AUTO_KEY, String(next));
      return next;
    });
  }, []);

  return { speak, stop, isSpeaking, autoRead, toggleAutoRead, supported };
}

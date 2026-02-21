"use client";

import { useEffect, useRef } from "react";
import { CuriousButton } from "@/components/CuriousButton";
import { FactDisplay } from "@/components/FactDisplay";
import { ErrorMessage } from "@/components/ErrorMessage";
import { TellMeMoreButton } from "@/components/TellMeMoreButton";
import { TTSControls } from "@/components/TTSControls";
import { useCurious } from "@/hooks/useCurious";
import { useTTS } from "@/hooks/useTTS";

export function CuriousApp() {
  const { status, fact, error, askCurious, tellMeMore } = useCurious();
  const { speak, stop, isSpeaking, autoRead, toggleAutoRead, supported } =
    useTTS();
  const prevFactRef = useRef<string | null>(null);

  // Auto-read new facts
  useEffect(() => {
    if (fact && fact !== prevFactRef.current && autoRead) {
      speak(fact);
    }
    prevFactRef.current = fact;
  }, [fact, autoRead, speak]);

  const isThinking = status === "thinking";

  return (
    <>
      <CuriousButton status={status} onClick={askCurious} />
      {fact && <FactDisplay fact={fact} />}
      {error && <ErrorMessage message={error} />}
      {(status === "done" || (status === "thinking" && fact)) && (
        <TellMeMoreButton onClick={tellMeMore} loading={isThinking} />
      )}
      <TTSControls
        autoRead={autoRead}
        isSpeaking={isSpeaking}
        supported={supported}
        onToggleAutoRead={toggleAutoRead}
        onSpeak={() => fact && speak(fact)}
        onStop={stop}
        hasFact={!!fact}
      />
    </>
  );
}

"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { CuriousButton } from "@/components/CuriousButton";
import { FactDisplay } from "@/components/FactDisplay";
import { ErrorMessage } from "@/components/ErrorMessage";
import { TellMeMoreButton } from "@/components/TellMeMoreButton";
import { TTSControls } from "@/components/TTSControls";
import { ThumbsControl } from "@/components/ThumbsControl";
import { useCurious } from "@/hooks/useCurious";
import { useTTS } from "@/hooks/useTTS";
import styles from "./CuriousApp.module.css";

export function CuriousApp() {
  const { status, fact, error, storyId, kind, askCurious, tellMeMore } =
    useCurious();
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
      {fact && <ThumbsControl key={storyId} kind={kind} />}
      <p className={styles.attribution}>
        {fact && (
          <>
            <a
              href="https://www.openstreetmap.org/copyright"
              target="_blank"
              rel="noopener noreferrer"
            >
              © OpenStreetMap contributors
            </a>
            {" · "}
          </>
        )}
        <Link href="/privacy">Privacy</Link>
      </p>
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

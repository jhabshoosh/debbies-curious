"use client";

import { useRef, useState } from "react";
import type { StoryKind } from "@/hooks/useCurious";
import styles from "./FeedbackControl.module.css";

interface FeedbackControlProps {
  kind: StoryKind;
}

export function FeedbackControl({ kind }: FeedbackControlProps) {
  const [voted, setVoted] = useState(false);
  const sentRef = useRef(false);

  const vote = (choice: "up" | "down") => {
    if (sentRef.current) return;
    sentRef.current = true;
    setVoted(true);
    // Fire and forget: a failed vote must never affect the rest of the app.
    fetch("/api/feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ vote: choice, kind }),
    }).catch(() => {});
  };

  return (
    <div className={styles.feedback}>
      <div className={styles.buttons}>
        <button
          type="button"
          className={styles.button}
          onClick={() => vote("up")}
          aria-label="Thumbs up"
        >
          <span aria-hidden="true">👍</span>
        </button>
        <button
          type="button"
          className={styles.button}
          onClick={() => vote("down")}
          aria-label="Thumbs down"
        >
          <span aria-hidden="true">👎</span>
        </button>
      </div>
      <p role="status" className={styles.thanks}>
        {voted ? "Thank you!" : ""}
      </p>
    </div>
  );
}

"use client";

import { useRef, useState } from "react";
import styles from "./FeedbackControl.module.css";

export type FeedbackVote = "up" | "down";
export type FeedbackKind = "first" | "more";

interface FeedbackControlProps {
  kind: FeedbackKind;
}

export function FeedbackControl({ kind }: FeedbackControlProps) {
  const [voted, setVoted] = useState(false);
  const sentRef = useRef(false);

  const vote = (choice: FeedbackVote) => {
    if (sentRef.current) return;
    sentRef.current = true;
    setVoted(true);
    // Fire and forget: a failed vote must never disturb the user.
    try {
      fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ vote: choice, kind }),
      }).catch(() => {});
    } catch {
      // ignore
    }
  };

  return (
    <div className={styles.feedback}>
      <div className={styles.buttons}>
        <button
          type="button"
          className={styles.button}
          aria-label="Thumbs up"
          disabled={voted}
          onClick={() => vote("up")}
        >
          <span aria-hidden="true">👍</span>
        </button>
        <button
          type="button"
          className={styles.button}
          aria-label="Thumbs down"
          disabled={voted}
          onClick={() => vote("down")}
        >
          <span aria-hidden="true">👎</span>
        </button>
      </div>
      <div role="status" className={styles.thanks}>
        {voted && <span>Thanks for letting us know!</span>}
      </div>
    </div>
  );
}

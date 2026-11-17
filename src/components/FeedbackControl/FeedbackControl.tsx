"use client";

import { useRef, useState } from "react";
import styles from "./FeedbackControl.module.css";

export type FeedbackKind = "first" | "more";

interface FeedbackControlProps {
  kind: FeedbackKind;
}

export function FeedbackControl({ kind }: FeedbackControlProps) {
  const [voted, setVoted] = useState(false);
  const sentRef = useRef(false);

  function vote(choice: "up" | "down") {
    if (sentRef.current) return;
    sentRef.current = true;
    setVoted(true);
    // Fire and forget: a failed vote must never get in the user's way.
    try {
      fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ vote: choice, kind }),
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  return (
    <div className={styles.feedback}>
      <div className={styles.buttons}>
        <button
          type="button"
          className={styles.button}
          onClick={() => vote("up")}
          disabled={voted}
          aria-label="Thumbs up"
        >
          <span aria-hidden="true">👍</span>
        </button>
        <button
          type="button"
          className={styles.button}
          onClick={() => vote("down")}
          disabled={voted}
          aria-label="Thumbs down"
        >
          <span aria-hidden="true">👎</span>
        </button>
      </div>
      <div role="status" className={styles.thanks}>
        {voted && "Thanks for your vote!"}
      </div>
    </div>
  );
}

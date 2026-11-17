"use client";

import { useRef, useState } from "react";
import styles from "./ThumbsControl.module.css";

type Vote = "up" | "down";

interface ThumbsControlProps {
  kind: "first" | "more";
}

export function ThumbsControl({ kind }: ThumbsControlProps) {
  const [voted, setVoted] = useState(false);
  const sentRef = useRef(false);

  const sendVote = (vote: Vote) => {
    if (sentRef.current) return;
    sentRef.current = true;
    setVoted(true);
    // Fire and forget: a failed vote must never bother the user.
    void fetch("/api/feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ vote, kind }),
    }).catch(() => {});
  };

  return (
    <div className={styles.container}>
      <div className={styles.buttons}>
        <button
          type="button"
          className={styles.button}
          aria-label="Thumbs up"
          disabled={voted}
          onClick={() => sendVote("up")}
        >
          <span aria-hidden="true">👍</span>
        </button>
        <button
          type="button"
          className={styles.button}
          aria-label="Thumbs down"
          disabled={voted}
          onClick={() => sendVote("down")}
        >
          <span aria-hidden="true">👎</span>
        </button>
      </div>
      <p role="status" className={styles.thanks}>
        {voted ? "Thanks for letting us know!" : ""}
      </p>
    </div>
  );
}

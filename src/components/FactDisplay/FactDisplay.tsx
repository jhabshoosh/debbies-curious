"use client";

import styles from "./FactDisplay.module.css";

interface FactDisplayProps {
  fact: string;
}

export function FactDisplay({ fact }: FactDisplayProps) {
  return (
    <div className={styles.card} role="status" aria-live="polite">
      <p className={styles.text}>{fact}</p>
    </div>
  );
}

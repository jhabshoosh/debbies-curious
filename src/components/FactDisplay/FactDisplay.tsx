"use client";

import styles from "./FactDisplay.module.css";

interface FactDisplayProps {
  fact: string;
}

export function FactDisplay({ fact }: FactDisplayProps) {
  return (
    <div className={styles.card} role="status" aria-live="polite">
      <p className={styles.text} dir="auto">
        {fact}
      </p>
      <a
        className={styles.attribution}
        href="https://www.openstreetmap.org/copyright"
        target="_blank"
        rel="noopener noreferrer"
      >
        © OpenStreetMap contributors
      </a>
    </div>
  );
}

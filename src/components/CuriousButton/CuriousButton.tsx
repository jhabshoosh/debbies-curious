"use client";

import styles from "./CuriousButton.module.css";

type CuriousStatus = "idle" | "locating" | "thinking" | "done" | "error";

interface CuriousButtonProps {
  status: CuriousStatus;
  onClick: () => void;
}

const BUTTON_LABELS: Record<CuriousStatus, string> = {
  idle: "I'm Curious!",
  locating: "Finding you...",
  thinking: "Thinking...",
  done: "I'm Curious!",
  error: "Try Again",
};

export function CuriousButton({ status, onClick }: CuriousButtonProps) {
  const isLoading = status === "locating" || status === "thinking";
  const label = BUTTON_LABELS[status];

  return (
    <button
      className={styles.button}
      onClick={onClick}
      disabled={isLoading}
      aria-busy={isLoading}
      aria-label={isLoading ? `${label} Please wait.` : label}
    >
      {isLoading && <span className={styles.spinner} aria-hidden="true" />}
      <span>{label}</span>
    </button>
  );
}

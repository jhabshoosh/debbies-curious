"use client";

import styles from "./TellMeMoreButton.module.css";

interface TellMeMoreButtonProps {
  onClick: () => void;
  loading: boolean;
}

export function TellMeMoreButton({ onClick, loading }: TellMeMoreButtonProps) {
  return (
    <button
      className={styles.button}
      onClick={onClick}
      disabled={loading}
      aria-busy={loading}
    >
      {loading && <span className={styles.spinner} aria-hidden="true" />}
      <span>{loading ? "Thinking..." : "Tell Me More!"}</span>
    </button>
  );
}

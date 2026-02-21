"use client";

import styles from "./ErrorMessage.module.css";

interface ErrorMessageProps {
  message: string;
}

export function ErrorMessage({ message }: ErrorMessageProps) {
  return (
    <div className={styles.container} role="alert">
      <p className={styles.text}>{message}</p>
    </div>
  );
}

"use client";

import styles from "./TTSControls.module.css";

interface TTSControlsProps {
  autoRead: boolean;
  isSpeaking: boolean;
  supported: boolean;
  onToggleAutoRead: () => void;
  onSpeak: () => void;
  onStop: () => void;
  hasFact: boolean;
}

export function TTSControls({
  autoRead,
  isSpeaking,
  supported,
  onToggleAutoRead,
  onSpeak,
  onStop,
  hasFact,
}: TTSControlsProps) {
  if (!supported) return null;

  return (
    <div className={styles.controls}>
      <label className={styles.toggle}>
        <input
          type="checkbox"
          checked={autoRead}
          onChange={onToggleAutoRead}
          className={styles.checkbox}
        />
        <span className={styles.slider} />
        <span className={styles.label}>Auto-read</span>
      </label>

      {hasFact && (
        <button
          className={styles.speakButton}
          onClick={isSpeaking ? onStop : onSpeak}
          aria-label={isSpeaking ? "Stop reading" : "Read aloud"}
        >
          {isSpeaking ? "Stop" : "Read Aloud"}
        </button>
      )}
    </div>
  );
}

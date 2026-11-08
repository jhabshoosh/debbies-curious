import type { Metadata } from "next";
import Link from "next/link";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Privacy - Debbie's Curious",
};

export default function PrivacyPage() {
  return (
    <div className={styles.page}>
      <main className={styles.main}>
        <h1 className={styles.title}>Privacy</h1>
        <p>Here is how Debbie&apos;s Curious treats your information.</p>
        <h2 className={styles.heading}>Your location</h2>
        <p>We use your location only to find the name of your place.</p>
        <p>
          Your location is sent to OpenStreetMap&apos;s geocoding service to
          turn it into a place name.
        </p>
        <p>
          Only the place name, not your coordinates, goes to the AI that writes
          the story.
        </p>
        <p>We never store or log your precise location.</p>
        <h2 className={styles.heading}>Everything else</h2>
        <p>There are no accounts.</p>
        <p>There are no ads.</p>
        <p>Stories come from an AI, so they may contain mistakes.</p>
        <Link href="/">Back to the main screen</Link>
      </main>
    </div>
  );
}

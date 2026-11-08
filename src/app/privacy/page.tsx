import type { Metadata } from "next";
import Link from "next/link";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Privacy - Debbie's Curious",
};

export default function PrivacyPage() {
  return (
    <main className={styles.page}>
      <h1 className={styles.title}>Privacy</h1>
      <p>Here is what happens when you tap the button.</p>

      <h2 className={styles.heading}>Your location</h2>
      <p>We use your location only to find the name of the place you are in.</p>
      <p>
        Your location is sent to OpenStreetMap&apos;s geocoding service to turn
        it into a place name.
      </p>
      <p>We never store or log your precise location.</p>

      <h2 className={styles.heading}>The story</h2>
      <p>
        Only the place name, not your coordinates, goes to the AI that writes
        the story.
      </p>
      <p>The stories come from an AI, so they may contain mistakes.</p>

      <h2 className={styles.heading}>The rest</h2>
      <p>There are no accounts.</p>
      <p>There are no ads.</p>

      <Link href="/" className={styles.back}>
        Back to the main screen
      </Link>
    </main>
  );
}

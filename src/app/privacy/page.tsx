import Link from "next/link";
import styles from "./page.module.css";

export const metadata = {
  title: "Privacy – Debbie's Curious",
};

export default function PrivacyPage() {
  return (
    <div className={styles.page}>
      <main className={styles.main}>
        <h1 className={styles.title}>Privacy</h1>
        <p>We use your location only to find the place name.</p>
        <p>
          Your location is sent to OpenStreetMap&apos;s geocoding service to
          turn it into a place name.
        </p>
        <p>Only the place name goes to the AI that writes your story.</p>
        <p>Your coordinates are not sent to the AI.</p>
        <p>We never store or log your precise location.</p>
        <p>There are no accounts and no ads.</p>
        <p>Stories come from an AI, so they may contain mistakes.</p>
        <p>
          <Link href="/">Back to the main screen</Link>
        </p>
      </main>
    </div>
  );
}

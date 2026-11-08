import Link from "next/link";
import styles from "./page.module.css";

export const metadata = {
  title: "Privacy - Debbie's Curious",
};

export default function PrivacyPage() {
  return (
    <div className={styles.page}>
      <main className={styles.main}>
        <h1 className={styles.title}>Privacy</h1>

        <h2 className={styles.heading}>Your location</h2>
        <p>We use your location only to find the place name.</p>
        <p>
          Your location is sent to OpenStreetMap&apos;s geocoding service to
          turn it into a place name.
        </p>
        <p>We do not store or log your precise location.</p>

        <h2 className={styles.heading}>The AI</h2>
        <p>Only the place name goes to the AI that writes the story.</p>
        <p>Your coordinates are not sent to the AI.</p>
        <p>Stories come from an AI and may contain mistakes.</p>

        <h2 className={styles.heading}>The rest</h2>
        <p>There are no accounts.</p>
        <p>There are no ads.</p>

        <Link href="/" className={styles.back}>
          Back to Debbie&apos;s Curious
        </Link>
      </main>
    </div>
  );
}

import styles from "./page.module.css";
import { CuriousApp } from "./CuriousApp";

export default function Home() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <h1 className={styles.title}>Debbie&apos;s Curious</h1>
        <p className={styles.subtitle}>
          What&apos;s the story about this place?
        </p>
      </header>
      <main className={styles.main}>
        <CuriousApp />
      </main>
    </div>
  );
}

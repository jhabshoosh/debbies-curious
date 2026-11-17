import Link from "next/link";
import styles from "./page.module.css";

export default function PrivacyPage() {
  return (
    <main className={styles.page}>
      <h1>Privacy</h1>
      <p>
        <Link href="/">Back to the app</Link>
      </p>

      <h2>Your location</h2>
      <p>
        When you press the button, the app asks your phone where you are. We use
        your location only to find the name of the place and tell you a story
        about it. The app does not store your location. We never save it.
      </p>

      <h2>Where your information goes</h2>
      <p>
        Your location goes to OpenStreetMap. They turn it into a place name.
        Then the place name goes to the story writer, which is OpenAI or
        Anthropic. Stories you have already heard on the same visit go along
        too, so you get something new.
      </p>

      <h2>What is kept</h2>
      <p>
        The app holds your internet address in its memory for a short time. This
        lets us stop too many requests from one person. It is lost when the
        service restarts.
      </p>
      <p>
        If you turn on Auto-read, your phone remembers that choice. It stays on
        your phone. We do not receive it.
      </p>

      <h2>Thumbs up and thumbs down</h2>
      <p>
        You can give a story a thumbs up or a thumbs down. This is your choice.
        A vote records only the up or down choice, a rough time, and whether the
        story was a first story or a tell me more story.
      </p>
      <p>A vote does not record your location, the story, or who you are.</p>

      <h2>What we do not know</h2>
      <p>
        OpenStreetMap, OpenAI, Anthropic and the company that hosts the app may
        keep some information. We do not know what they keep. We cannot say, and
        we will not guess. Please read their own privacy notices to learn more.
      </p>
    </main>
  );
}

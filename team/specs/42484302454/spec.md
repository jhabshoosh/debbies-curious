# Privacy page

Facts checked in code: `src/lib/geocode.ts` sends latitude/longitude to `nominatim.openstreetmap.org`; `src/app/api/curious/route.ts` passes only the formatted place name (plus earlier stories) to the LLM provider; the only logging is `console.error` of the error object (no coordinates); there are no accounts, ads or analytics; localStorage holds only the read-aloud preference; the rate limiter keeps the IP in memory only.

1. A route `/privacy` exists: `src/app/privacy/page.tsx` default-exports a synchronous React component (no props) that renders the page.
2. The main page (`src/app/page.tsx`) contains a link to `/privacy` inside a `<footer>` (role `contentinfo`) that is outside `<main>`.
3. The first screen is unchanged: the footer link is an `<a>`, not a button, and the main page renders no more buttons than `CuriousApp` alone does. The title, subtitle and `CuriousApp` are still rendered.
4. The privacy page has a single `<h1>` and is written in short sentences (no sentence over 30 words).
5. It says the location is used only to find the place name.
6. It says the location is sent to OpenStreetMap's geocoding service to turn it into a place name.
7. It says only the place name, not the coordinates, goes to the AI provider that writes the story.
8. It says the app does not store or log the precise location.
9. It says there are no accounts and no ads.
10. It says stories come from an AI and may contain mistakes.
11. It does not mention analytics (nothing like that exists).
12. It has a link back to `/` (the main screen).

Not testable by tests: whether the wording is actually plain and friendly. Reviewers should read it. Tests check only for key facts using loose patterns, not exact wording. Because the tests match per sentence, each fact should sit in one sentence (for example, "We never store or log your precise location." and "Only the place name, not your coordinates, goes to the AI.").

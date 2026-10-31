# OpenStreetMap attribution

Every fact the app shows is built from a Nominatim reverse-geocode lookup, so
the attribution goes wherever a fact is shown.

1. While a fact is on screen, the page contains a link with the exact text
   `© OpenStreetMap contributors`.
2. That link's `href` is exactly `https://www.openstreetmap.org/copyright`.
3. The link is visible without any tap: it is not inside a collapsed
   `<details>`, not `hidden`, not `aria-hidden`, and not hidden by styles.
4. It appears together with the fact, in the same render, after the first
   "I'm Curious!" press succeeds.
5. It is still shown after "Tell me more" replaces the fact.
6. It is not shown before any fact exists (initial idle screen).
7. It is not shown when the request failed and no fact is displayed, because
   no Nominatim data is displayed then.
8. Exactly one attribution link is shown at a time (no duplicates).

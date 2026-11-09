# Friendly tap-failure messages

1. When the browser cannot reach the server (fetch rejects, e.g. "Failed to fetch"), the alert shows a plain message about the internet/connection and says trying again is worthwhile. The raw browser text is never shown.
2. If the server replies with a non-OK status and a body that is not JSON, the user sees a friendly message that suggests trying again, never a parse error or raw body.
3. `POST /api/curious` returns 503 with a friendly error when the story provider fails with status 429, 503 or 529 (unavailable / out of capacity). This message differs from the generic-failure message (500) and from our own rate-limit message (429).
4. Any other unexpected server failure returns 500 with a generic friendly message. Neither 500 nor 503 bodies contain the underlying error text, keys or paths.
5. On the client, offline, service unavailable (503), generic failure (500) and rate limited (429) each show a different message, and each says to try again/later. The 503 case must not echo the server's raw error string.
6. Location denied explains that access was denied and what to do (enable it in settings). Location timeout says it timed out and invites another try.
7. After any failure the main button is enabled; tapping it again retries without reload, clears the error, and shows the fact on success.
8. The first screen is unchanged: one "I'm Curious!" button and no alert.

Notes: wording is checked only by loose keyword patterns (internet/connection, again/later, settings/enable). Whether a message is truly "plain and friendly" beyond those cues needs human review.

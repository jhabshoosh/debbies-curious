# Friendly failures for every tap

Applies to the full app (`CuriousApp`): the first "I'm Curious!" tap and the "Tell Me More!" tap.

1. Any failure shows a short message in a `role="alert"` region. It never contains raw technical text: no "Failed to fetch", no JSON/parse error text ("Unexpected token", "SyntaxError"), no error names ("TypeError"), no upstream or provider error strings (e.g. an API-key or "OpenAI" message returned in the response body), and never "undefined" or "null".
2. The message says what happened and what to do next (e.g. check the connection / try again / allow location).
3. No internet or a dropped connection (fetch rejects) gives a friendly message (1, 2).
4. The server or story service failing (non-OK status such as 500/502/503 with an arbitrary, technical or non-JSON body) gives a friendly message (1, 2). The server's own text must not be shown unless it is one of the two existing messages in 8.
5. A successful (200) response whose body is not JSON, or has no usable `fact`, gives a friendly message and shows no fact.
6. A request that never answers ends within 60 seconds with a friendly "took too long, try again" message. The button stops spinning and is usable again. It must still be waiting at 5 seconds. The test's fetch honours `AbortSignal`.
7. Location trouble (permission denied, position unavailable, timeout, no geolocation support, or the geolocation call throwing) gives a friendly message (1, 2) and no request is sent to the server.
8. The existing daily-limit message ("Debbie's stories are resting for today. Please come back tomorrow!", HTTP 503) and the too-many-taps message ("Too many requests. Please wait a moment and try again.", HTTP 429) are still shown as they are.
9. After any failure one tap on the main button (a "Try Again" button) retries; if it succeeds the fact is shown and the error disappears. This also holds after a failed "Tell Me More!".
10. The first screen is unchanged: one "I'm Curious!" button and no alert.

Not testable here: the exact wording and tone of messages. Tests only check the rules above (no raw technical text, a next-step word, a sensible length).

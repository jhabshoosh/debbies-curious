# Daily app-wide limit on story requests

Env var: `DAILY_REQUEST_LIMIT` (positive integer), read at request time.

1. Each `POST /api/curious` that reaches the AI provider counts toward one app-wide daily total, shared across all IPs.
2. Once the total equals the limit, further requests do not call the AI provider (the provider factory is not even used).
3. The over-limit response has status 503 and `{ error }` where the message mentions that stories are resting and to try again tomorrow. It must not blame the user or sound like a crash (no "wrong", "error", "failed", "too many", "invalid").
4. `DAILY_REQUEST_LIMIT` sets the limit (e.g. `3` allows exactly 3 stories, then blocks).
5. With the variable unset, a default applies: at least 50 and at most 5000 requests per day.
6. The count resets on the next calendar day (UTC): after the day changes, requests succeed again.
7. Requests rejected by the per-IP rate limit (429) or by coordinate validation (400) do not use up the daily budget.
8. Per-IP rate limiting (10/min/IP, 429) and the successful `{ fact }` response are unchanged. The client hook already shows the server's `error` text, so no UI change is needed.

Not testable here: how the message reads to a person; tests check key phrases only.

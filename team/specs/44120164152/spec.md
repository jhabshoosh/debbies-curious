# Optional thumbs up / thumbs down on a story

## Contract chosen by this spec

- Endpoint: `POST /api/feedback` (new route at `src/app/api/feedback/route.ts`, exporting `POST`).
- Request body: JSON `{ "vote": "up" | "down", "kind": "first" | "more" }`. `kind` is `"first"` for a story from the main button and `"more"` for a story from "Tell me more".
- The client sends exactly those two keys and nothing else.

## Acceptance criteria

1. Before any story exists (first screen), the page has exactly one button, the main "I'm Curious!" button, and no thumbs control. The control is also absent while locating, thinking for a first story, and after an error.
2. Once a story is shown, a thumbs control appears below the story text in the page. It has two native `<button>`s, one with an accessible name matching `/thumbs up/i` and one matching `/thumbs down/i`. Because they are native buttons, Enter and Space activate them, and they are in the tab order.
3. The control never blocks or delays anything else. While a vote request is still pending (never resolves), the main button, "Tell Me More!" and "Read Aloud" all stay enabled and work. A new story can still be fetched and shown.
4. Tapping a vote shows a brief thank-you, in an element inside a live region (`role="status"` or `aria-live`) so screen readers announce it.
5. A vote sends one `POST /api/feedback` with body exactly `{ vote, kind }`. The body has no coordinates, place name, story text or other identifier. `kind` is `"first"` for a story from the main button, including after a "Tell me more" and a restart, and `"more"` for a "Tell me more" story.
6. For one story, a vote can't be sent twice. A second tap, a double-click, or tapping the other button sends no further request.
7. Each new story (main button or "Tell me more") gets a fresh control. It has no thank-you, is usable, and can send one vote for that story.
8. If the vote request fails (network rejection or a non-2xx response), the user sees no alert and no error or failure wording. The story stays, and the main button keeps its normal label (not "Try Again") and stays usable.
9. The server route validates input. It returns a 2xx for a valid vote and 400 for an invalid `vote`, an invalid `kind`, or a body that isn't valid JSON.
10. The server route never logs, through any `console` method, anything from the request other than the vote, the kind and a coarse timestamp. Coordinates, place names, story text, and IP or other identifying headers (including extra body fields a client might send) never appear in log output.
11. The privacy page says plainly what a vote does and doesn't record. It mentions votes or thumbs. It says a vote records only the up or down choice, a rough time, and whether the story was a first story or a "tell me more" story. It says a vote doesn't record location, the story or who you are.

## Review-only (not testable here)

- Tap targets are large for older users (at least 48px, ideally larger), and keyboard focus is visibly styled. jsdom has no layout, so the reviewer should check the CSS Module.
- The server timestamp is coarse (for example rounded to the hour or day), not millisecond-precise. How the vote is recorded (for example a single structured log line) is up to the Builder. Test 10 only forbids sensitive data.
- Visual placement and styling of the thank-you.

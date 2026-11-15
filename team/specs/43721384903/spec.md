# Privacy page (run 43721384903)

Facts checked against the code today:

- `src/hooks/useCurious.ts`: the browser sends latitude, longitude and earlier stories to `/api/curious`. Nothing is saved on the device except the Auto-read setting in `localStorage` (`useTTS.ts`).
- `src/app/api/curious/route.ts`: coordinates go to OpenStreetMap's geocoder (`src/lib/geocode.ts`). Only the resulting place name, plus earlier stories from the same visit, goes to the story provider (OpenAI or Anthropic, `src/lib/llm/prompts.ts`). The app doesn't write coordinates to a database.
- `src/lib/rate-limit.ts` and `daily-limit.ts`: the visitor's IP address is held in server memory for the rate limit. It is lost on restart.
- No cookies, accounts or analytics exist in the code. The page must not promise or advertise them.
- What OpenStreetMap, OpenAI, Anthropic or the host keep is unknown to the team.

## Acceptance criteria

1. The first screen (before any press) still has exactly one button, the "I'm Curious" button. It has no dialog, banner or consent step.
2. The first screen has a small link whose text includes "privacy". It points to `/privacy`, opens in the same tab, and is a link, not a button.
3. When the OpenStreetMap credit is shown (after a story), the privacy link sits next to it: within the same container, at most one level above the credit link.
4. `/privacy` (`src/app/privacy/page.tsx`, default export) renders one top-level heading that includes "privacy".
5. The page has a link back to the app (`href="/"`) with plain wording containing "back" or "return".
6. The page says the location is used only to find the place name and tell a story, and that the app does not store it.
7. The page says the coordinates go to OpenStreetMap, and the place name goes to the story provider (OpenAI or Anthropic).
8. The page says whether anything is kept: the visitor's internet address is held in memory for rate limiting. It also says the Auto-read choice stays on the device.
9. The page says plainly that the team does not know what the outside services keep, and does not guess.
10. The page is written for readers aged 55-75: no jargon (API, JSON, LLM, geocoder, Nominatim, endpoint, in-memory), and sentences average 20 words or fewer.
11. The page doesn't claim to use cookies, accounts or analytics. Tests can't prove this, so a reviewer should read the page for it.

Tests can't judge whether the wording is easy to read. The jargon and sentence-length checks are a rough proxy, so a reviewer should still read the page.

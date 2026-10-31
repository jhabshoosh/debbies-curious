# Honest stories: no invented details

Applies to `LOCATION_SYSTEM_PROMPT` in `src/lib/llm/prompts.ts`, which both providers send as the system prompt.

1. The system prompt no longer tells the model never to say it doesn't know, or that there is always something interesting about any place.
2. The system prompt tells the model that when it has little reliable knowledge of the exact place, it should share something true about the wider area (region, county, landscape, etc.) instead.
3. The system prompt tells the model to say plainly that it is talking about the wider area when it does this, rather than passing it off as being about the exact spot.
4. The system prompt forbids making up or inventing facts, specifically names, dates and events.
5. The system prompt keeps the warm, friendly, conversational voice, and tells the model the fallback keeps that same voice.
6. The existing limit of 2-3 sentences maximum is kept.
7. The existing rules remain: ONE fact, no GPS coordinates mentioned, stay geographically accurate (no confusing the place with other cities or regions).
8. `buildUserPrompt` behaves as before (question about the location, plus a numbered list of previous facts with a "DIFFERENT" request).

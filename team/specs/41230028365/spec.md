# Honest fallback for unknown places

1. `LOCATION_SYSTEM_PROMPT` no longer tells the model never to say it doesn't know (no "Never say ... don't know" instruction).
2. The prompt tells the model that when it has little reliable knowledge of the exact place, it should share something true about the wider area (region, county, etc.).
3. The prompt tells the model to say explicitly that it is talking about the wider area in that case.
4. The prompt forbids making up names, dates or events.
5. The prompt keeps the warm, conversational voice, including for the wider-area fallback.
6. The prompt keeps the "2-3 sentences maximum" length limit.
7. The prompt still requires staying geographically accurate and not mentioning GPS coordinates.
8. `buildUserPrompt` is unchanged: it names the location and lists previous facts when given.

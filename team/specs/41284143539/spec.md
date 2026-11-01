# Fresh location on every tap

1. A tap requests a fresh position: the first geolocation request must not accept a cached position older than about a minute (`maximumAge` < 60000 ms).
2. A passenger who has moved since the last tap gets the new coordinates sent to `/api/curious`, not the earlier ones.
3. If the fresh request fails with a timeout or position-unavailable, the hook retries accepting a recent cached position (up to ~5 minutes) and resolves with it instead of failing.
4. The fresh attempt is bounded: its `timeout` is at most 10000 ms, so the fallback happens quickly.
5. If permission is denied, the tap fails with the existing denied message and does not fall back.
6. If neither fresh nor cached position is available, the error is reported as before.
7. Location is never logged (no `console.*` calls) and never stored (`localStorage`/`sessionStorage` untouched).
8. The one-button first screen is unchanged (no UI changes; existing component tests still pass). Not separately tested here.

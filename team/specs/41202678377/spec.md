# Show OpenStreetMap attribution on results

Every result the app shows comes from a location that `/api/curious` looked up through Nominatim. The OpenStreetMap and Nominatim usage policies require attribution wherever such a result is displayed.

## Acceptance criteria

1. While a fact is displayed, the page shows a link with the text `© OpenStreetMap contributors`.
2. That link's `href` is exactly `https://www.openstreetmap.org/copyright`.
3. The attribution is visible without any extra tap. It is rendered in the same view as the fact. It is not inside a `<details>` element, a hidden element, an `aria-hidden` element, or a collapsed menu or tooltip.
4. The attribution is still shown after "Tell me more" loads another fact, and it appears only once.
5. The attribution is not shown before any result exists (idle state).
6. The attribution is not shown when the app displays only an error and no result.
7. If the link opens in a new tab (`target="_blank"`), it also has `rel` containing `noopener`.

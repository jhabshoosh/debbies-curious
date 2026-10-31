# OpenStreetMap / Nominatim attribution

Every fact the app shows is produced from a Nominatim reverse-geocode, so the
attribution accompanies every displayed fact.

1. When a fact is displayed, the page shows the text `© OpenStreetMap contributors`.
2. That text is a link (`<a>`) whose `href` is `https://www.openstreetmap.org/copyright`.
3. The attribution is shown for the initial fact and stays shown while a
   "tell me more" request is loading and after it completes.
4. The attribution is not shown when no fact is displayed (idle, locating, or
   error with no fact), since no Nominatim-derived result is on screen.
5. It is visible without extra taps: it is plain rendered content, not inside a
   collapsed `<details>`, a tooltip, a dialog, or an element that is
   `hidden` / `aria-hidden`.
6. The link text is readable on a phone screen: the attribution is not
   rendered with `display: none` or `visibility: hidden` inline.
7. The attribution appears exactly once.

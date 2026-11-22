# Friendly tap failures

Tests: `friendly-errors.test.tsx` (renders `CuriousApp`, mocks `fetch` and `navigator.geolocation`).

"Friendly" means the alert text is a plain sentence that contains no technical
vocabulary (error class names, "fetch", "JSON", "Unexpected", HTTP status
numbers, markup characters, "gateway") and suggests trying again / later.

1. Lost internet (`fetch` rejects, `navigator.onLine` false): the alert is friendly and mentions the internet/connection.
2. Flaky connection (`fetch` rejects with a network error while online): the alert is friendly and mentions the connection/network.
3. Gateway error page (non-JSON HTML body, e.g. 502): the alert is friendly; no parse-error text leaks.
4. A 200 response whose body is unreadable: the alert is friendly.
5. Story service down (500 with a technical `error` string, or 503 with an empty body): the alert is friendly; technical server text is not shown.
6. Every failure above leaves exactly one "Try Again" button as the way to retry.
7. The daily-limit message ("Debbie's stories are resting for today…") and the rate-limit message ("Too many requests…") are still shown to the user as written by the server.
8. Denied location still shows a message about location access and how to fix it, and no request is sent.
9. Retrying after a failure that then succeeds shows the fact and clears the alert.
10. A failed "Tell me more" after a success is also friendly.
11. A successful tap is unchanged: POST `/api/curious` with coordinates, fact shown, no alert.

Not testable here: the exact wording, and the visual look of the message.

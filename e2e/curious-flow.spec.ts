import { test, expect } from "@playwright/test";

test.describe("Curious Flow", () => {
  test("page loads with button visible", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByRole("heading", { name: /debbie/i })).toBeVisible();
    await expect(
      page.getByRole("button", { name: /i'm curious/i })
    ).toBeVisible();
  });

  test("button shows loading state on click", async ({ page, context }) => {
    // Mock geolocation
    await context.grantPermissions(["geolocation"]);
    await context.setGeolocation({ latitude: 40.7128, longitude: -74.006 });

    // Mock API response
    await page.route("**/api/curious", async (route) => {
      await new Promise((r) => setTimeout(r, 100));
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          fact: "New York City was originally called New Amsterdam!",
        }),
      });
    });

    await page.goto("/");

    const button = page.getByRole("button", { name: /i'm curious/i });
    await button.click();

    // Should show a loading state (either "Finding you..." or "Thinking...")
    await expect(button).toBeDisabled();

    // Wait for fact to appear
    await expect(
      page.getByText("New York City was originally called New Amsterdam!")
    ).toBeVisible({ timeout: 10000 });

    // Button should be re-enabled
    await expect(button).toBeEnabled();
  });

  test("displays error when API fails", async ({ page, context }) => {
    await context.grantPermissions(["geolocation"]);
    await context.setGeolocation({ latitude: 40.7128, longitude: -74.006 });

    await page.route("**/api/curious", async (route) => {
      await route.fulfill({
        status: 500,
        contentType: "application/json",
        body: JSON.stringify({
          error: "Something went wrong. Please try again.",
        }),
      });
    });

    await page.goto("/");

    await page.getByRole("button", { name: /i'm curious/i }).click();

    await expect(page.getByRole("alert")).toBeVisible({ timeout: 10000 });
    await expect(page.getByText(/something went wrong/i)).toBeVisible();
  });

  test("TTS auto-read toggle is visible and checkable", async ({ page }) => {
    await page.goto("/");

    const toggle = page.getByRole("checkbox");
    await expect(toggle).toBeVisible();
    await expect(toggle).toBeChecked();

    await toggle.click();
    await expect(toggle).not.toBeChecked();
  });
});

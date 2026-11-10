const DEFAULT_DAILY_LIMIT = 1000;

let currentDay = "";
let count = 0;

function getDailyLimit(): number {
  const parsed = Number.parseInt(process.env.DAILY_REQUEST_LIMIT ?? "", 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_DAILY_LIMIT;
}

// Counts one request toward the app-wide daily total (UTC day), if budget remains.
export function consumeDailyBudget(): { allowed: boolean } {
  const today = new Date().toISOString().slice(0, 10);
  if (today !== currentDay) {
    currentDay = today;
    count = 0;
  }

  if (count >= getDailyLimit()) {
    return { allowed: false };
  }

  count++;
  return { allowed: true };
}

// For testing
export function resetDailyLimit(): void {
  currentDay = "";
  count = 0;
}

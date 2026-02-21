interface RateLimitEntry {
  timestamps: number[];
}

const store = new Map<string, RateLimitEntry>();

const MAX_REQUESTS = 10;
const WINDOW_MS = 60 * 1000; // 1 minute

export function checkRateLimit(key: string): { allowed: boolean } {
  const now = Date.now();
  const entry = store.get(key) || { timestamps: [] };

  // Remove timestamps outside the window
  entry.timestamps = entry.timestamps.filter((t) => now - t < WINDOW_MS);

  if (entry.timestamps.length >= MAX_REQUESTS) {
    store.set(key, entry);
    return { allowed: false };
  }

  entry.timestamps.push(now);
  store.set(key, entry);
  return { allowed: true };
}

// For testing
export function resetRateLimitStore(): void {
  store.clear();
}

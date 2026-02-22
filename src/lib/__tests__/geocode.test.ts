import { describe, it, expect, vi, beforeEach } from "vitest";
import { reverseGeocode, formatLocationName } from "../geocode";
import type { LocationInfo } from "../geocode";

const mockFetch = vi.fn();

beforeEach(() => {
  vi.stubGlobal("fetch", mockFetch);
  mockFetch.mockReset();
});

describe("reverseGeocode", () => {
  it("parses a Nominatim response into LocationInfo", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          display_name:
            "123, Front Street, East Meadow, Nassau County, New York, 11554, United States",
          address: {
            house_number: "123",
            road: "Front Street",
            neighbourhood: "East Meadow",
            city: "Hempstead",
            county: "Nassau County",
            state: "New York",
            country: "United States",
          },
        }),
    });

    const result = await reverseGeocode(40.7142, -73.5593);

    expect(result.neighborhood).toBe("East Meadow");
    expect(result.city).toBe("Hempstead");
    expect(result.county).toBe("Nassau County");
    expect(result.state).toBe("New York");
    expect(result.country).toBe("United States");
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("nominatim.openstreetmap.org"),
      expect.objectContaining({
        headers: expect.objectContaining({
          "User-Agent": expect.any(String),
        }),
      })
    );
  });

  it("throws on non-OK response", async () => {
    mockFetch.mockResolvedValue({ ok: false, status: 500 });
    await expect(reverseGeocode(0, 0)).rejects.toThrow("Geocoding failed: 500");
  });
});

describe("formatLocationName", () => {
  it("formats a full location", () => {
    const info: LocationInfo = {
      neighborhood: "East Meadow",
      city: "Hempstead",
      county: "Nassau County",
      state: "New York",
      country: "United States",
      displayName: "full display name",
    };
    expect(formatLocationName(info)).toBe(
      "East Meadow, Hempstead, Nassau County, New York, United States"
    );
  });

  it("skips null fields", () => {
    const info: LocationInfo = {
      neighborhood: null,
      city: "Paris",
      county: null,
      state: null,
      country: "France",
      displayName: "Paris, France",
    };
    expect(formatLocationName(info)).toBe("Paris, France");
  });

  it("skips county when same as city", () => {
    const info: LocationInfo = {
      neighborhood: null,
      city: "San Francisco",
      county: "San Francisco",
      state: "California",
      country: "United States",
      displayName: "San Francisco, CA",
    };
    expect(formatLocationName(info)).toBe(
      "San Francisco, California, United States"
    );
  });

  it("falls back to displayName when all fields are null", () => {
    const info: LocationInfo = {
      neighborhood: null,
      city: null,
      county: null,
      state: null,
      country: null,
      displayName: "Middle of the Ocean",
    };
    expect(formatLocationName(info)).toBe("Middle of the Ocean");
  });
});

interface NominatimResponse {
  address: {
    house_number?: string;
    road?: string;
    neighbourhood?: string;
    suburb?: string;
    city?: string;
    town?: string;
    village?: string;
    hamlet?: string;
    county?: string;
    state?: string;
    country?: string;
  };
  display_name: string;
}

export interface LocationInfo {
  neighborhood: string | null;
  city: string | null;
  county: string | null;
  state: string | null;
  country: string | null;
  displayName: string;
}

export async function reverseGeocode(
  latitude: number,
  longitude: number
): Promise<LocationInfo> {
  const url = `https://nominatim.openstreetmap.org/reverse?lat=${latitude}&lon=${longitude}&format=json&addressdetails=1&zoom=16`;

  const response = await fetch(url, {
    headers: {
      "User-Agent": "DebbiesCurious/1.0 (https://debbies-curious.vercel.app)",
    },
  });

  if (!response.ok) {
    throw new Error(`Geocoding failed: ${response.status}`);
  }

  const data: NominatimResponse = await response.json();
  const addr = data.address;

  return {
    neighborhood: addr.neighbourhood || addr.suburb || null,
    city: addr.city || addr.town || addr.village || addr.hamlet || null,
    county: addr.county || null,
    state: addr.state || null,
    country: addr.country || null,
    displayName: data.display_name,
  };
}

export function formatLocationName(info: LocationInfo): string {
  const parts: string[] = [];

  if (info.neighborhood) parts.push(info.neighborhood);
  if (info.city) parts.push(info.city);
  if (info.county && info.county !== info.city) parts.push(info.county);
  if (info.state) parts.push(info.state);
  if (info.country) parts.push(info.country);

  return parts.length > 0 ? parts.join(", ") : info.displayName;
}

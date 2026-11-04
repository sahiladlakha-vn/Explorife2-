/** Mirrors `lib/dev-preview/fixtures.ts`'s first trip ID — kept in sync by hand since e2e/ isn't allowed to import server-only code. */
export const TRIP_ID = "11111111-1111-1111-1111-111111111111";

export const TRIP_TABS = ["trip", "itinerary", "dashboard", "bookings"] as const;

export function tripTabUrl(tab: (typeof TRIP_TABS)[number]): string {
  return `/dev-preview/trips/${TRIP_ID}/${tab}`;
}

export const BREAKPOINTS = [
  { name: "desktop-xl", width: 1440, height: 900 },
  { name: "desktop", width: 1024, height: 900 },
  { name: "tablet", width: 768, height: 1024 },
  { name: "mobile", width: 375, height: 812 },
] as const;

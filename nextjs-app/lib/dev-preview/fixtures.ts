import "server-only";
import type { Trip } from "@/lib/generated/prisma/client";

/**
 * Fake trips for `/dev-preview/*` — no DB, no auth. Fixed IDs so Playwright
 * can link directly to a known trip. Covers the three date states
 * `TripList` groups by (ongoing/upcoming, far-future, past) and includes one
 * long name to exercise truncation.
 */
const OWNER_ID = "00000000-0000-0000-0000-000000000001";

function fixtureTrip(overrides: Partial<Trip> & Pick<Trip, "id" | "name" | "startDate" | "endDate">): Trip {
  return {
    ownerId: OWNER_ID,
    location: "Vietnam",
    budgetVnd: BigInt(15_000_000),
    currency: "VND",
    vibe: null,
    templateId: null,
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    locationLat: null,
    locationLng: null,
    description: null,
    coverImageUrl: null,
    ...overrides,
  };
}

const now = new Date();
const daysFromNow = (days: number) => new Date(now.getTime() + days * 86_400_000);

export const DEV_PREVIEW_TRIPS: Trip[] = [
  fixtureTrip({
    id: "11111111-1111-1111-1111-111111111111",
    name: "Sapa Trekking Adventure",
    startDate: daysFromNow(-2),
    endDate: daysFromNow(5),
  }),
  fixtureTrip({
    id: "22222222-2222-2222-2222-222222222222",
    name: "Da Nang & Hoi An Beach Week With Friends",
    startDate: daysFromNow(60),
    endDate: daysFromNow(67),
  }),
  fixtureTrip({
    id: "33333333-3333-3333-3333-333333333333",
    name: "Hanoi Weekend",
    startDate: daysFromNow(-30),
    endDate: daysFromNow(-28),
  }),
];

export function getDevPreviewTrip(tripId: string): Trip | undefined {
  return DEV_PREVIEW_TRIPS.find((trip) => trip.id === tripId);
}

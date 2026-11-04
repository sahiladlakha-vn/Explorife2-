import "server-only";
import type { Trip } from "@/lib/generated/prisma/client";
import type { ItineraryStopInput } from "@/lib/trips/itinerary";

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

function fixtureStop(
  overrides: Partial<ItineraryStopInput> & Pick<ItineraryStopInput, "id" | "day" | "slot" | "sortOrder">,
): ItineraryStopInput {
  return {
    gemId: null,
    customPayload: null,
    priceVnd: null,
    transitMode: null,
    transitLine: null,
    transitDurationMin: null,
    transitCostVnd: null,
    startTime: null,
    notes: null,
    gem: null,
    isBooked: false,
    bookingAmountVnd: null,
    ...overrides,
  };
}

/**
 * Three days of real Sa Pa stops for the "Sapa Trekking Adventure" fixture
 * trip — days 4-8 are deliberately left empty so the itinerary page exercises
 * both the populated and "Nothing planned yet" states. Coordinates are real
 * Sa Pa landmarks; `gemCoords` uses the `{lat, lng}` object shape, matching
 * what `Gem.toInsert()` actually writes (see
 * `supabase/migrations/20260815000100_seed_real_gems.sql`). Photo URLs are
 * placeholder paths in the same style as
 * `supabase/migrations/20260826000100_seed_test_gem_editorial_content.sql`'s
 * test fixture, not real images.
 */
const SAPA_ITINERARY_STOPS: ItineraryStopInput[] = [
  fixtureStop({
    id: "d1-morning-market",
    day: 1,
    slot: "morning",
    sortOrder: 0,
    gemId: "gem-sapa-market",
    priceVnd: 0,
    gem: {
      gemName: "Sapa Market",
      category: "food",
      gemCoords: { lat: 22.3364, lng: 103.8438 },
      photoUrl: "https://images.unsplash.com/photo-sapa-market.jpg",
      estDurationMin: 60,
    },
  }),
  fixtureStop({
    id: "d1-morning-catcat",
    day: 1,
    slot: "morning",
    sortOrder: 1,
    gemId: "gem-cat-cat-village",
    priceVnd: 80_000,
    transitMode: "Walk",
    transitDurationMin: 20,
    notes: "Entrance ticket booth is right past the parking lot.",
    gem: {
      gemName: "Cat Cat Village",
      category: "heritage",
      gemCoords: { lat: 22.327, lng: 103.829 },
      photoUrl: null,
      estDurationMin: 90,
    },
  }),
  fixtureStop({
    id: "d1-afternoon-cablecar",
    day: 1,
    slot: "afternoon",
    sortOrder: 0,
    gemId: "gem-fansipan-cable-car",
    priceVnd: null,
    transitMode: "Taxi",
    transitDurationMin: 35,
    transitCostVnd: 300_000,
    startTime: new Date("2000-01-01T13:30:00.000Z"),
    gem: {
      gemName: "Fansipan Cable Car",
      category: "landmark",
      gemCoords: { lat: 22.3024, lng: 103.7761 },
      photoUrl: null,
      estDurationMin: 180,
    },
  }),
  fixtureStop({
    id: "d1-evening-dinner",
    day: 1,
    slot: "evening",
    sortOrder: 0,
    customPayload: { title: "Dinner at hotel", lat: 22.3364, lng: 103.8438 },
    priceVnd: 150_000,
    isBooked: true,
    bookingAmountVnd: 150_000,
    notes: "Try the salmon hotpot — ask for the upstairs terrace table with the valley view.",
  }),
  fixtureStop({
    id: "d2-morning-summit",
    day: 2,
    slot: "morning",
    sortOrder: 0,
    gemId: "gem-fansipan-summit",
    priceVnd: 0,
    transitMode: "Cable car",
    transitLine: "Fansipan Legend",
    transitDurationMin: 20,
    transitCostVnd: 750_000,
    gem: {
      gemName: "Fansipan Summit",
      category: "landmark",
      gemCoords: { lat: 22.3047, lng: 103.7752 },
      photoUrl: "https://images.unsplash.com/photo-fansipan-summit.jpg",
      estDurationMin: 90,
    },
  }),
  fixtureStop({
    id: "d2-afternoon-valley",
    day: 2,
    slot: "afternoon",
    sortOrder: 0,
    gemId: "gem-muong-hoa-valley",
    priceVnd: null,
    gem: {
      gemName: "Muong Hoa Valley Viewpoint",
      category: "viewpoint",
      gemCoords: { lat: 22.299, lng: 103.846 },
      photoUrl: null,
      estDurationMin: 45,
    },
  }),
  fixtureStop({
    id: "d2-evening-free",
    day: 2,
    slot: "evening",
    sortOrder: 0,
    customPayload: { title: "Free evening — explore town" },
    priceVnd: null,
    notes: "Wander Sapa's night market stalls near the church square.",
  }),
  fixtureStop({
    id: "d3-morning-waterfall",
    day: 3,
    slot: "morning",
    sortOrder: 0,
    gemId: "gem-silver-waterfall",
    priceVnd: 20_000,
    transitMode: "Taxi",
    transitDurationMin: 45,
    transitCostVnd: 400_000,
    gem: {
      gemName: "Silver Waterfall",
      category: "nature",
      gemCoords: { lat: 22.358, lng: 103.769 },
      photoUrl: null,
      estDurationMin: 50,
    },
  }),
  fixtureStop({
    id: "d3-afternoon-taphin",
    day: 3,
    slot: "afternoon",
    sortOrder: 0,
    gemId: "gem-ta-phin-village",
    priceVnd: 50_000,
    isBooked: true,
    bookingAmountVnd: 50_000,
    transitMode: "Motorbike",
    transitDurationMin: 50,
    transitCostVnd: 200_000,
    notes: "Local Red Dao guide meets at the village gate.",
    gem: {
      gemName: "Ta Phin Village",
      category: "heritage",
      gemCoords: { lat: 22.3836, lng: 103.8707 },
      photoUrl: null,
      estDurationMin: 120,
    },
  }),
];

const DEV_PREVIEW_ITINERARY_STOPS: Record<string, ItineraryStopInput[]> = {
  "11111111-1111-1111-1111-111111111111": SAPA_ITINERARY_STOPS,
};

export function getDevPreviewItineraryStops(tripId: string): ItineraryStopInput[] {
  return DEV_PREVIEW_ITINERARY_STOPS[tripId] ?? [];
}

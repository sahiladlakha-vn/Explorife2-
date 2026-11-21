import "server-only";
import type { AdminDashboardData } from "@/components/features/dashboard/AdminDashboard";
import { fillBookingMix } from "@/lib/dashboard/booking-mix";
import { lastAndPreviousSevenDays, percentChange } from "@/lib/dashboard/booking-trends";
import { failed, ok } from "@/lib/dashboard/section";
import type {
  BookingMixEntry,
  BookingValueSummary,
  BookingVelocity,
  ByPeriod,
  DestinationRanking,
  ModerationStats,
  WeekTrip,
} from "@/lib/dashboard/types";

/**
 * Fake `/admin/dashboard` data — no DB, no auth, and no clock: every date is a
 * fixed literal (a week in November 2026), so the preview renders identically
 * on every visit and `new Date()` never runs in a static route. The real page
 * computes "today" and "this week" in SQL instead. Typed directly against
 * `AdminDashboardData`, so it is structurally guaranteed to match what the
 * real page passes to the same `AdminDashboard` component.
 *
 * Three variants: the populated dashboard, an all-empty one (every card's
 * empty state), and a partial failure (some queries failed, the rest loaded —
 * the per-card error states).
 */

/** Thursday 19 Nov 2026, in the week Monday 16 – Sunday 22. */
const TODAY = "2026-11-19";
const WEEK_START = "2026-11-16";

/** The 14 Vietnam days ending TODAY, oldest first. */
const LAST_14_DAYS = [
  "2026-11-06",
  "2026-11-07",
  "2026-11-08",
  "2026-11-09",
  "2026-11-10",
  "2026-11-11",
  "2026-11-12",
  "2026-11-13",
  "2026-11-14",
  "2026-11-15",
  "2026-11-16",
  "2026-11-17",
  "2026-11-18",
  "2026-11-19",
];

function bookingValue(
  paid: number[],
  counts: number[],
  lifetime: { paidVnd: number; paidCount: number },
): BookingValueSummary {
  const daily = LAST_14_DAYS.map((day, i) => ({ day, count: counts[i]!, amountVnd: paid[i]! }));
  const { last7, prev7 } = lastAndPreviousSevenDays(paid);
  return { ...lifetime, daily, last7Vnd: last7, prev7Vnd: prev7, changePercent: percentChange(last7, prev7) };
}

function velocity(counts: number[]): BookingVelocity {
  return {
    daily: LAST_14_DAYS.map((day, i) => ({ day, count: counts[i]! })),
    total: counts.reduce((sum, c) => sum + c, 0),
  };
}

const usage = (items: [string, number, boolean][]): DestinationRanking => ({
  mode: "usage",
  items: items.map(([location, tripCount, featured]) => ({ location, tripCount, featured })),
});

const trip = (id: string, name: string, location: string, startDate: string, endDate: string): WeekTrip => ({
  id,
  name,
  location,
  startDate,
  endDate,
});

const POPULATED_MIX: ByPeriod<BookingMixEntry[]> = {
  month: fillBookingMix([
    { bookingType: "flight", count: 41, amountVnd: 118_000_000 },
    { bookingType: "stay", count: 58, amountVnd: 164_000_000 },
    { bookingType: "activity", count: 27, amountVnd: 22_000_000 },
    { bookingType: "transport", count: 19, amountVnd: 14_000_000 },
  ]),
  quarter: fillBookingMix([
    { bookingType: "flight", count: 142, amountVnd: 410_000_000 },
    { bookingType: "stay", count: 203, amountVnd: 580_000_000 },
    { bookingType: "activity", count: 98, amountVnd: 85_000_000 },
    { bookingType: "transport", count: 97, amountVnd: 60_000_000 },
  ]),
  year: fillBookingMix([
    { bookingType: "flight", count: 612, amountVnd: 1_780_000_000 },
    { bookingType: "stay", count: 840, amountVnd: 2_420_000_000 },
    { bookingType: "activity", count: 402, amountVnd: 360_000_000 },
    { bookingType: "transport", count: 388, amountVnd: 240_000_000 },
  ]),
};

const POPULATED_DESTINATIONS: ByPeriod<DestinationRanking> = {
  month: usage([
    ["sapa", 12, true],
    ["da nang", 9, true],
    ["hanoi", 6, false],
    ["phu quoc", 4, false],
    ["hoi an", 3, false],
    ["ha long bay", 2, true],
  ]),
  quarter: usage([
    ["sapa", 42, true],
    ["da nang", 35, true],
    ["hoi an", 28, false],
    ["ha long bay", 24, true],
    ["phu quoc", 19, false],
    ["hanoi", 16, false],
  ]),
  year: usage([
    ["da nang", 160, true],
    ["sapa", 151, true],
    ["hanoi", 118, false],
    ["hoi an", 104, false],
    ["ha long bay", 97, true],
    ["phu quoc", 88, false],
  ]),
};

const moderationStats = (
  verifiedCount: number,
  pendingCount: number,
  avgTurnaroundHours: number | null,
): ModerationStats => {
  const totalListings = verifiedCount + pendingCount;
  return {
    totalListings,
    verifiedCount,
    pendingCount,
    percentage: totalListings === 0 ? 0 : Math.round((verifiedCount / totalListings) * 100),
    avgTurnaroundHours,
  };
};

const POPULATED_MODERATION_BY_PERIOD: ByPeriod<ModerationStats> = {
  month: moderationStats(22, 9, 3.1),
  quarter: moderationStats(88, 21, 5.4),
  year: moderationStats(281, 45, 4.3),
};

export const DEV_PREVIEW_ADMIN_DASHBOARD: AdminDashboardData = {
  admin: { role: "super_admin", name: "Linh" },
  totalUsers: ok(1842),
  trips: ok({ activeCount: 37, completedCount: 128, totalCount: 212, percentage: 17, completedPercentage: 60 }),
  upcomingBookingCoverage: ok({ upcomingCount: 64, withBookingCount: 48, percentage: 75 }),
  moderation: ok(moderationStats(281, 45, 4.3)),
  bookingValue: ok(
    bookingValue(
      [
        35_000_000, 52_000_000, 18_000_000, 64_000_000, 41_000_000, 80_000_000, 90_000_000, 60_000_000, 45_000_000,
        92_000_000, 55_000_000, 110_000_000, 38_000_000, 50_000_000,
      ],
      [3, 5, 2, 6, 4, 7, 5, 6, 4, 8, 5, 9, 3, 4],
      { paidVnd: 1_245_000_000, paidCount: 318 },
    ),
  ),
  bookingVelocity: ok(velocity([3, 5, 2, 6, 4, 7, 5, 6, 8, 4, 9, 7, 10, 6])),
  bookingFunnel: ok({ toBook: 540, booked: 210, paid: 120 }),
  upcomingWeek: ok({
    weekStart: WEEK_START,
    today: TODAY,
    trips: [
      trip("fixture-trip-1", "Da Nang & Hoi An Beach Week", "Da Nang", "2026-11-14", "2026-11-17"),
      trip("fixture-trip-2", "Sapa Trekking Adventure", "Sapa", "2026-11-18", "2026-11-23"),
      trip("fixture-trip-3", "Hanoi Weekend", "Hanoi", "2026-11-20", "2026-11-22"),
      trip("fixture-trip-4", "Ha Long Bay Cruise", "Ha Long Bay", "2026-11-17", "2026-11-19"),
    ],
    nextTrip: trip("fixture-trip-5", "Phu Quoc Island Getaway", "Phu Quoc", "2026-11-30", "2026-12-06"),
  }),
  recentBookings: ok([
    { id: "fixture-booking-1", tripName: "Sapa Trekking Adventure", bookingType: "flight", amountVnd: 2_500_000, status: "paid", createdAt: "2026-11-19T08:30:00Z" },
    { id: "fixture-booking-2", tripName: "Da Nang & Hoi An Beach Week", bookingType: "stay", amountVnd: 4_800_000, status: "paid", createdAt: "2026-11-18T14:10:00Z" },
    { id: "fixture-booking-3", tripName: "Hanoi Weekend", bookingType: "activity", amountVnd: null, status: "to_book", createdAt: "2026-11-18T09:45:00Z" },
    { id: "fixture-booking-4", tripName: "Phu Quoc Island Getaway", bookingType: "transport", amountVnd: 650_000, status: "booked", createdAt: "2026-11-17T17:20:00Z" },
    { id: "fixture-booking-5", tripName: "Ha Long Bay Cruise", bookingType: "stay", amountVnd: 6_200_000, status: "paid", createdAt: "2026-11-17T11:05:00Z" },
    { id: "fixture-booking-6", tripName: "Ho Chi Minh City Food Tour", bookingType: "activity", amountVnd: 300_000, status: "booked", createdAt: "2026-11-16T19:40:00Z" },
    { id: "fixture-booking-7", tripName: "Sapa Trekking Adventure", bookingType: "stay", amountVnd: 3_100_000, status: "paid", createdAt: "2026-11-16T07:15:00Z" },
    { id: "fixture-booking-8", tripName: "Da Nang & Hoi An Beach Week", bookingType: "flight", amountVnd: null, status: "to_book", createdAt: "2026-11-15T13:00:00Z" },
  ]),
  destinations: ok(POPULATED_DESTINATIONS),
  bookingMix: ok(POPULATED_MIX),
  moderationByPeriod: ok(POPULATED_MODERATION_BY_PERIOD),
};

const EMPTY_BY_PERIOD = <T>(value: T): ByPeriod<T> => ({ month: value, quarter: value, year: value });

/** A brand-new environment: everything loaded fine and there is simply no data yet. */
export const DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY: AdminDashboardData = {
  admin: { role: "super_admin", name: null },
  totalUsers: ok(1),
  trips: ok({ activeCount: 0, completedCount: 0, totalCount: 0, percentage: 0, completedPercentage: 0 }),
  upcomingBookingCoverage: ok({ upcomingCount: 0, withBookingCount: 0, percentage: 0 }),
  moderation: ok(moderationStats(0, 0, null)),
  bookingValue: ok(bookingValue(Array(14).fill(0), Array(14).fill(0), { paidVnd: 0, paidCount: 0 })),
  bookingVelocity: ok(velocity(Array(14).fill(0))),
  bookingFunnel: ok({ toBook: 0, booked: 0, paid: 0 }),
  upcomingWeek: ok({ weekStart: WEEK_START, today: TODAY, trips: [], nextTrip: null }),
  recentBookings: ok([]),
  destinations: ok(EMPTY_BY_PERIOD<DestinationRanking>({ mode: "usage", items: [] })),
  bookingMix: ok(EMPTY_BY_PERIOD(fillBookingMix([]))),
  moderationByPeriod: ok(EMPTY_BY_PERIOD(moderationStats(0, 0, null))),
};

/**
 * Some queries failed, the rest loaded: the failed cards show their own error
 * state while every other card (and the page) is untouched.
 */
export const DEV_PREVIEW_ADMIN_DASHBOARD_ERRORS: AdminDashboardData = {
  ...DEV_PREVIEW_ADMIN_DASHBOARD,
  totalUsers: failed(),
  bookingValue: failed(),
  bookingFunnel: failed(),
  upcomingWeek: failed(),
  recentBookings: failed(),
  destinations: failed(),
  bookingMix: failed(),
};

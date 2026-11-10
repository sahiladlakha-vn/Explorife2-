import "server-only";
import { cacheLife } from "next/cache";
import { prisma } from "@/lib/db";
import { normalizeDestination } from "./destination-normalize";

/**
 * Read-only aggregate queries for `/admin/dashboard`. Every export here is a
 * shared, non-personalized number (no userId/region argument anywhere — see
 * MIGRATION_PLAN.md-style note in app/admin/dashboard/page.tsx for why
 * regional_admin can't be data-scoped yet), so each is cached with `"use
 * cache"` and shared across every admin who loads the dashboard within the
 * cache window. Admin-identity/role resolution happens in the page instead
 * of here, since it reads cookies — Cache Components forbids a `"use
 * cache"` function from reading dynamic data.
 *
 * Prisma bypasses RLS like every other `lib/server/*.ts` module, but there's
 * no per-user authorization check *in this file* — callers (the dashboard
 * page) must call `requireAdminOrRedirect`/`requireAdmin` first. These
 * functions are safe to share across admins precisely because they contain
 * no per-user data.
 */

const DASHBOARD_CACHE_LIFE = { stale: 30, revalidate: 60, expire: 300 } as const;

const VIETNAM_UTC_OFFSET_MS = 7 * 60 * 60 * 1000;

/**
 * Vietnam has a fixed UTC+7 offset with no DST, so shifting the clock by a
 * constant is exact. Only needed for `getUpcomingTrips` below — every other
 * widget does its day-bucketing in raw SQL via `AT TIME ZONE
 * 'Asia/Ho_Chi_Minh'`, or needs no timezone conversion at all because it
 * compares absolute instants (`now() - interval`) rather than calendar days.
 */
function vietnamTodayAsUtcDate(): Date {
  const shifted = new Date(Date.now() + VIETNAM_UTC_OFFSET_MS);
  return new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()));
}

// --- Total users -----------------------------------------------------------

export async function getTotalUsers(): Promise<number> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);
  return prisma.profile.count();
}

// --- Trips in Progress (dial) ------------------------------------------------

export interface TripsInProgress {
  activeCount: number;
  totalCount: number;
  percentage: number;
}

interface TripsInProgressRow {
  activeCount: number;
  totalCount: number;
}

/** % of all trips whose [startDate, endDate] contains today (Vietnam calendar date). */
export async function getTripsInProgress(): Promise<TripsInProgress> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const rows = await prisma.$queryRaw<TripsInProgressRow[]>`
    SELECT
      count(*) FILTER (
        WHERE start_date <= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
          AND end_date >= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
      )::int AS "activeCount",
      count(*)::int AS "totalCount"
    FROM trips
  `;
  // Unconditional aggregate (no GROUP BY) over `trips` — always exactly one row.
  const row = rows[0]!;
  const percentage = row.totalCount === 0 ? 0 : Math.round((row.activeCount / row.totalCount) * 100);
  return { activeCount: row.activeCount, totalCount: row.totalCount, percentage };
}

// --- Upcoming booking coverage (pill) ----------------------------------------

export interface UpcomingBookingCoverage {
  upcomingCount: number;
  withBookingCount: number;
  percentage: number;
}

interface UpcomingBookingCoverageRow {
  upcomingCount: number;
  withBookingCount: number;
}

/** % of upcoming trips (startDate after today, Vietnam calendar date) that have >=1 booking. */
export async function getUpcomingBookingCoverage(): Promise<UpcomingBookingCoverage> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const rows = await prisma.$queryRaw<UpcomingBookingCoverageRow[]>`
    SELECT
      count(*)::int AS "upcomingCount",
      count(*) FILTER (
        WHERE EXISTS (SELECT 1 FROM trip_bookings b WHERE b.trip_id = t.id)
      )::int AS "withBookingCount"
    FROM trips t
    WHERE t.start_date > (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
  `;
  const row = rows[0]!;
  const percentage = row.upcomingCount === 0 ? 0 : Math.round((row.withBookingCount / row.upcomingCount) * 100);
  return { upcomingCount: row.upcomingCount, withBookingCount: row.withBookingCount, percentage };
}

// --- Moderation (verification queue) -----------------------------------------

export interface ModerationStats {
  totalListings: number;
  verifiedCount: number;
  pendingCount: number;
  percentage: number;
  avgTurnaroundHours: number | null;
}

interface ModerationStatsRow {
  totalListings: number;
  verifiedCount: number;
  pendingCount: number;
  avgTurnaroundSeconds: number | null;
}

/** % of attractions+restaurants verified, plus avg time from created_at to verified_at for the ones that are. Soft-deleted listings excluded. */
export async function getModerationStats(): Promise<ModerationStats> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const rows = await prisma.$queryRaw<ModerationStatsRow[]>`
    SELECT
      count(*)::int AS "totalListings",
      count(*) FILTER (WHERE verification_status = 'verified')::int AS "verifiedCount",
      count(*) FILTER (WHERE verification_status = 'pending')::int AS "pendingCount",
      avg(extract(epoch FROM (verified_at - created_at)))
        FILTER (WHERE verification_status = 'verified' AND verified_at IS NOT NULL)::float8 AS "avgTurnaroundSeconds"
    FROM (
      SELECT verification_status, verified_at, created_at FROM attractions WHERE deleted_at IS NULL
      UNION ALL
      SELECT verification_status, verified_at, created_at FROM restaurants WHERE deleted_at IS NULL
    ) listings
  `;
  const row = rows[0]!;
  const percentage = row.totalListings === 0 ? 0 : Math.round((row.verifiedCount / row.totalListings) * 100);
  return {
    totalListings: row.totalListings,
    verifiedCount: row.verifiedCount,
    pendingCount: row.pendingCount,
    percentage,
    avgTurnaroundHours: row.avgTurnaroundSeconds === null ? null : row.avgTurnaroundSeconds / 3600,
  };
}

// --- Booking Value (Paid) ----------------------------------------------------

export interface BookingValueDay {
  day: string;
  count: number;
  amountVnd: number;
}

export interface BookingValueSummary {
  paidVnd: number;
  paidCount: number;
  daily: BookingValueDay[];
}

interface BookingValueDayRow {
  day: string;
  count: number;
  amountVnd: number;
}

/**
 * Lifetime paid total (headline number) plus the last 7 days of paid
 * bookings bucketed by Vietnam calendar day (mini bar chart). `amountVnd:
 * null` means unpriced/TBD and must stay excluded from the sum — SQL `sum()`
 * already ignores NULLs on its own, so no `?? 0` coalescing happens on
 * individual rows here.
 */
export async function getBookingValueSummary(): Promise<BookingValueSummary> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const [agg, dailyRows] = await Promise.all([
    prisma.tripBooking.aggregate({
      where: { status: "paid" },
      _sum: { amountVnd: true },
      _count: true,
    }),
    prisma.$queryRaw<BookingValueDayRow[]>`
      SELECT
        ((created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date)::text AS day,
        count(*)::int AS count,
        coalesce(sum(amount_vnd), 0)::float8 AS "amountVnd"
      FROM trip_bookings
      WHERE status = 'paid' AND created_at >= now() - interval '7 days'
      GROUP BY 1
      ORDER BY 1
    `,
  ]);

  return {
    paidVnd: Number(agg._sum.amountVnd ?? BigInt(0)),
    paidCount: agg._count,
    daily: dailyRows,
  };
}

// --- Booking funnel: To Book -> Booked -> Paid (cumulative) ------------------

export interface BookingFunnel {
  toBook: number;
  booked: number;
  paid: number;
}

/** Cumulative stages: toBook = every booking; booked = booked+paid; paid = paid only. */
export async function getBookingFunnel(): Promise<BookingFunnel> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const grouped = await prisma.tripBooking.groupBy({
    by: ["status"],
    _count: true,
  });
  const counts = Object.fromEntries(grouped.map((g) => [g.status, g._count]));
  const toBookOnly = counts["to_book"] ?? 0;
  const bookedOnly = counts["booked"] ?? 0;
  const paidOnly = counts["paid"] ?? 0;

  return {
    toBook: toBookOnly + bookedOnly + paidOnly,
    booked: bookedOnly + paidOnly,
    paid: paidOnly,
  };
}

// --- Upcoming trips (timeline) -----------------------------------------------

export interface UpcomingTripItem {
  id: string;
  name: string;
  location: string;
  startDate: string;
  endDate: string;
}

/** Next 6 trips starting after today (Vietnam calendar date), earliest first. */
export async function getUpcomingTrips(): Promise<UpcomingTripItem[]> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const trips = await prisma.trip.findMany({
    where: { startDate: { gt: vietnamTodayAsUtcDate() } },
    orderBy: { startDate: "asc" },
    take: 6,
    select: { id: true, name: true, location: true, startDate: true, endDate: true },
  });

  return trips.map((trip) => ({
    id: trip.id,
    name: trip.name,
    location: trip.location,
    startDate: trip.startDate.toISOString(),
    endDate: trip.endDate.toISOString(),
  }));
}

// --- Recent bookings (dark card) ---------------------------------------------

export interface RecentBookingItem {
  id: string;
  tripName: string;
  bookingType: string;
  amountVnd: number | null;
  status: string;
  createdAt: string;
}

/** Last 8 bookings. Trip name only, never the booking creator's email/phone. */
export async function getRecentBookings(): Promise<RecentBookingItem[]> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const bookings = await prisma.tripBooking.findMany({
    orderBy: { createdAt: "desc" },
    take: 8,
    select: {
      id: true,
      bookingType: true,
      amountVnd: true,
      status: true,
      createdAt: true,
      trip: { select: { name: true } },
    },
  });

  return bookings.map((booking) => ({
    id: booking.id,
    tripName: booking.trip.name,
    bookingType: booking.bookingType,
    amountVnd: booking.amountVnd === null ? null : Number(booking.amountVnd),
    status: booking.status,
    createdAt: booking.createdAt.toISOString(),
  }));
}

// --- Booking mix (replaces Lead/Traffic Attribution) -------------------------

export interface BookingMixEntry {
  bookingType: string;
  count: number;
  amountVnd: number;
}

/** Count + total amountVnd per bookingType, across all statuses. */
export async function getBookingMix(): Promise<BookingMixEntry[]> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const grouped = await prisma.tripBooking.groupBy({
    by: ["bookingType"],
    _count: true,
    _sum: { amountVnd: true },
  });

  return grouped.map((g) => ({
    bookingType: g.bookingType,
    count: g._count,
    amountVnd: Number(g._sum.amountVnd ?? BigInt(0)),
  }));
}

// --- Destination ranking (replaces Top Destinations) -------------------------

export interface DestinationUsageItem {
  location: string;
  tripCount: number;
  featured: boolean;
}

export interface DestinationEditorialItem {
  title: string;
}

export type DestinationRanking =
  | { mode: "usage"; items: DestinationUsageItem[] }
  | { mode: "editorial"; items: DestinationEditorialItem[] };

interface DestinationUsageRow {
  location: string;
  tripCount: number;
}

/**
 * Merges raw location groups that share a `normalizeDestination` key (e.g.
 * "Saigon" and "Ho Chi Minh City" trips both become one "Ho Chi Minh City"
 * row), summing their counts. The displayed label is whichever raw spelling
 * had the highest individual count within the merged group — not the
 * normalized key itself, which is just a matching key, not display text.
 * Rows are case-preserving (`trim(location)`, not lowercased) specifically
 * so that popularity contest is meaningful.
 */
function mergeByNormalizedDestination(rows: DestinationUsageRow[]): DestinationUsageRow[] {
  const merged = new Map<string, { label: string; labelCount: number; tripCount: number }>();

  for (const row of rows) {
    const key = normalizeDestination(row.location);
    const existing = merged.get(key);
    if (!existing) {
      merged.set(key, { label: row.location, labelCount: row.tripCount, tripCount: row.tripCount });
      continue;
    }
    existing.tripCount += row.tripCount;
    if (row.tripCount > existing.labelCount) {
      existing.label = row.location;
      existing.labelCount = row.tripCount;
    }
  }

  return [...merged.values()]
    .map(({ label, tripCount }) => ({ location: label, tripCount }))
    .sort((a, b) => b.tripCount - a.tripCount || a.location.localeCompare(b.location));
}

/**
 * Usage-ranked by `Trip.location`, merged across spellings that share a
 * `normalizeDestination` key over the last 90 days of trip creation, and
 * cross-referenced against `CuratedCollection.scopeValue` for a "Featured"
 * badge via the same normalizer. `CuratedCollection` has no FK to
 * `Trip`/`TripStop` at all, so this cross-reference is always a fuzzy
 * string match, not a real join. Falls back to the editorial
 * `CuratedCollection` ranking (labeled "Featured Destinations" by the
 * caller) when there's no usage data at all, e.g. a fresh environment.
 */
export async function getDestinationRanking(): Promise<DestinationRanking> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const usageRows = await prisma.$queryRaw<DestinationUsageRow[]>`
    SELECT trim(location) AS location, count(*)::int AS "tripCount"
    FROM trips
    WHERE created_at >= now() - interval '90 days'
    GROUP BY 1
  `;

  if (usageRows.length > 0) {
    const topDestinations = mergeByNormalizedDestination(usageRows).slice(0, 6);

    const destinations = await prisma.curatedCollection.findMany({
      where: { isDestination: true },
      select: { scopeValue: true },
    });
    const featuredScopes = new Set(destinations.map((d) => normalizeDestination(d.scopeValue)));

    return {
      mode: "usage",
      items: topDestinations.map((row) => ({
        location: row.location,
        tripCount: row.tripCount,
        featured: featuredScopes.has(normalizeDestination(row.location)),
      })),
    };
  }

  const editorial = await prisma.curatedCollection.findMany({
    where: { isDestination: true },
    orderBy: { sortOrder: "asc" },
    take: 6,
    select: { title: true },
  });
  return { mode: "editorial", items: editorial };
}

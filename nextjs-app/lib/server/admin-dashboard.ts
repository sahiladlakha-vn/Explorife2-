import "server-only";
import { cacheLife } from "next/cache";
import { prisma } from "@/lib/db";
import { fillBookingMix } from "@/lib/dashboard/booking-mix";
import {
  lastAndPreviousSevenDays,
  percentChange,
} from "@/lib/dashboard/booking-trends";
import {
  PERFORMANCE_PERIOD_DAYS,
  PERFORMANCE_PERIODS,
} from "@/lib/dashboard/periods";
import type {
  BookingFunnel,
  BookingMixEntry,
  BookingValueDay,
  BookingValueSummary,
  BookingVelocity,
  BookingVelocityDay,
  ByPeriod,
  DestinationRanking,
  ModerationStats,
  RecentBookingItem,
  TripsInProgress,
  UpcomingBookingCoverage,
  UpcomingWeek,
  WeekTrip,
} from "@/lib/dashboard/types";
import { addDays } from "@/lib/dashboard/week-strip";
import {
  destinationLabel,
  normalizeDestination,
} from "./destination-normalize";

/**
 * Read-only aggregate queries for `/admin/dashboard`. Every export here is a
 * shared, non-personalized number (no userId/region argument anywhere — see
 * MIGRATION_PLAN.md-style note in app/admin/dashboard/page.tsx for why
 * regional_admin can't be data-scoped yet), so each is cached with `"use
 * cache"` and shared across every admin who loads the dashboard within the
 * cache window. Admin-identity/role resolution happens in the page instead
 * of here, since it reads cookies — Cache Components forbids a `"use
 * cache"` function from reading dynamic data. (`cacheLife` below is the
 * `revalidate: 60` of this codebase: `cacheComponents: true` rejects the
 * segment-level `revalidate` export.)
 *
 * Prisma bypasses RLS like every other `lib/server/*.ts` module, but there's
 * no per-user authorization check *in this file* — callers (the dashboard
 * page) must call `requireAdminOrRedirect`/`requireAdmin` first. These
 * functions are safe to share across admins precisely because they contain
 * no per-user data.
 *
 * Time handling: every "today", "this week" and per-day bucket is computed in
 * SQL with `AT TIME ZONE 'Asia/Ho_Chi_Minh'`, never from JavaScript's clock, so
 * the results are Vietnam calendar days regardless of where the server runs.
 */

const DASHBOARD_CACHE_LIFE = { stale: 30, revalidate: 60, expire: 300 } as const;

const percentage = (part: number, total: number): number =>
  total === 0 ? 0 : Math.round((part / total) * 100);

// --- Total users -----------------------------------------------------------

export async function getTotalUsers(): Promise<number> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);
  return prisma.profile.count();
}

// --- Trips: in progress (dial / Active Trips KPI) and completed (pill) -------

interface TripsInProgressRow {
  activeCount: number;
  completedCount: number;
  totalCount: number;
}

/**
 * Active = [startDate, endDate] contains today; completed = endDate is before
 * today. Both as a share of all trips, by Vietnam calendar date.
 */
export async function getTripsInProgress(): Promise<TripsInProgress> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const rows = await prisma.$queryRaw<TripsInProgressRow[]>`
    SELECT
      count(*) FILTER (
        WHERE start_date <= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
          AND end_date >= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
      )::int AS "activeCount",
      count(*) FILTER (
        WHERE end_date < (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
      )::int AS "completedCount",
      count(*)::int AS "totalCount"
    FROM trips
  `;
  // Unconditional aggregate (no GROUP BY) over `trips` — always exactly one row.
  const row = rows[0]!;
  return {
    activeCount: row.activeCount,
    completedCount: row.completedCount,
    totalCount: row.totalCount,
    percentage: percentage(row.activeCount, row.totalCount),
    completedPercentage: percentage(row.completedCount, row.totalCount),
  };
}

// --- Upcoming booking coverage (pill) ----------------------------------------

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
  return {
    upcomingCount: row.upcomingCount,
    withBookingCount: row.withBookingCount,
    percentage: percentage(row.withBookingCount, row.upcomingCount),
  };
}

// --- Moderation (verification queue) -----------------------------------------

interface ModerationStatsRow {
  totalListings: number;
  verifiedCount: number;
  pendingCount: number;
  avgTurnaroundSeconds: number | null;
}

function toModerationStats(row: ModerationStatsRow): ModerationStats {
  return {
    totalListings: row.totalListings,
    verifiedCount: row.verifiedCount,
    pendingCount: row.pendingCount,
    percentage: percentage(row.verifiedCount, row.totalListings),
    avgTurnaroundHours:
      row.avgTurnaroundSeconds === null ? null : row.avgTurnaroundSeconds / 3600,
  };
}

/** % of attractions+restaurants verified, plus avg time from created_at to verified_at for the ones that are. Soft-deleted listings excluded. All time. */
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
  return toModerationStats(rows[0]!);
}

// --- Booking Value (Paid) ----------------------------------------------------

/**
 * Lifetime paid total (headline) plus the last 14 Vietnam days of paid
 * bookings, zero-filled so quiet days still get a bar. The card shows the last
 * 7 days by weekday and compares their total with the 7 days before (the
 * period-over-period badge). `amountVnd: null` means unpriced/TBD and stays
 * out of every sum — SQL `sum()` ignores NULLs on its own. This is user-logged
 * trip spend, not revenue.
 */
export async function getBookingValueSummary(): Promise<BookingValueSummary> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const [agg, daily] = await Promise.all([
    prisma.tripBooking.aggregate({
      where: { status: "paid" },
      _sum: { amountVnd: true },
      _count: true,
    }),
    prisma.$queryRaw<BookingValueDay[]>`
      WITH days AS (
        SELECT d::date AS day
        FROM generate_series(
          ((now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date - 13)::timestamp,
          (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date::timestamp,
          interval '1 day'
        ) AS d
      )
      SELECT
        days.day::text AS day,
        count(b.id)::int AS count,
        coalesce(sum(b.amount_vnd), 0)::float8 AS "amountVnd"
      FROM days
      LEFT JOIN trip_bookings b
        ON b.status = 'paid'
       AND (b.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date = days.day
      GROUP BY days.day
      ORDER BY days.day
    `,
  ]);

  const { last7, prev7 } = lastAndPreviousSevenDays(
    daily.map((day) => day.amountVnd),
  );

  return {
    paidVnd: Number(agg._sum.amountVnd ?? BigInt(0)),
    paidCount: agg._count,
    daily,
    last7Vnd: last7,
    prev7Vnd: prev7,
    changePercent: percentChange(last7, prev7),
  };
}

// --- Booking Velocity --------------------------------------------------------

/** Bookings created per Vietnam day over the last 14 days (any status), zero-filled. */
export async function getBookingVelocity(): Promise<BookingVelocity> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const daily = await prisma.$queryRaw<BookingVelocityDay[]>`
    WITH days AS (
      SELECT d::date AS day
      FROM generate_series(
        ((now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date - 13)::timestamp,
        (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date::timestamp,
        interval '1 day'
      ) AS d
    )
    SELECT
      days.day::text AS day,
      count(b.id)::int AS count
    FROM days
    LEFT JOIN trip_bookings b
      ON (b.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date = days.day
    GROUP BY days.day
    ORDER BY days.day
  `;

  return { daily, total: daily.reduce((sum, day) => sum + day.count, 0) };
}

// --- Booking funnel: To Book -> Booked -> Paid (cumulative) ------------------

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

// --- Upcoming trips (week strip) ---------------------------------------------

interface WeekBoundsRow {
  weekStart: string;
  today: string;
}

const WEEK_TRIP_SELECT = {
  id: true,
  name: true,
  location: true,
  startDate: true,
  endDate: true,
} as const;

function toWeekTrip(trip: {
  id: string;
  name: string;
  location: string;
  startDate: Date;
  endDate: Date;
}): WeekTrip {
  return {
    id: trip.id,
    name: trip.name,
    location: trip.location,
    // Trip dates are DATE columns (UTC midnight), so the ISO prefix is the calendar day.
    startDate: trip.startDate.toISOString().slice(0, 10),
    endDate: trip.endDate.toISOString().slice(0, 10),
  };
}

/**
 * The current Vietnam week (Monday–Sunday) and the trips overlapping it,
 * placed on the strip by startDate/endDate, plus the next trip after the week
 * so the card is never an empty box on a quiet week. The week bounds come from
 * Postgres (`date_trunc('week')` is Monday-based), not from JavaScript's clock.
 */
export async function getUpcomingWeek(): Promise<UpcomingWeek> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const [bounds] = await prisma.$queryRaw<WeekBoundsRow[]>`
    SELECT
      date_trunc('week', now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date::text AS "weekStart",
      (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date::text AS today
  `;
  const weekStart = bounds!.weekStart;
  const weekEnd = addDays(weekStart, 6);

  const [trips, nextTrip] = await Promise.all([
    prisma.trip.findMany({
      where: {
        startDate: { lte: new Date(`${weekEnd}T00:00:00Z`) },
        endDate: { gte: new Date(`${weekStart}T00:00:00Z`) },
      },
      orderBy: [{ startDate: "asc" }, { endDate: "asc" }],
      take: 12,
      select: WEEK_TRIP_SELECT,
    }),
    prisma.trip.findFirst({
      where: { startDate: { gt: new Date(`${weekEnd}T00:00:00Z`) } },
      orderBy: { startDate: "asc" },
      select: WEEK_TRIP_SELECT,
    }),
  ]);

  return {
    weekStart,
    today: bounds!.today,
    trips: trips.map(toWeekTrip),
    nextTrip: nextTrip ? toWeekTrip(nextTrip) : null,
  };
}

// --- Recent bookings (dark card) ---------------------------------------------

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

// --- Performance Overview: one result per Month / Quarter / Year window ------

/**
 * Runs `load` once per Performance Overview window (rolling 30 / 90 / 365
 * days) in parallel. The page ships all three results to the client so the
 * toggle switches instantly without another round trip.
 */
async function forEachPeriod<T>(
  load: (days: number) => Promise<T>,
): Promise<ByPeriod<T>> {
  const entries = await Promise.all(
    PERFORMANCE_PERIODS.map(
      async (period) =>
        [period, await load(PERFORMANCE_PERIOD_DAYS[period])] as const,
    ),
  );
  return Object.fromEntries(entries) as ByPeriod<T>;
}

// --- Booking mix -------------------------------------------------------------

async function bookingMixForDays(days: number): Promise<BookingMixEntry[]> {
  const rows = await prisma.$queryRaw<BookingMixEntry[]>`
    SELECT
      booking_type AS "bookingType",
      count(*)::int AS count,
      coalesce(sum(amount_vnd), 0)::float8 AS "amountVnd"
    FROM trip_bookings
    WHERE created_at >= now() - (${days}::int * interval '1 day')
    GROUP BY booking_type
  `;
  return fillBookingMix(rows);
}

/** Count + total amountVnd per bookingType (all statuses), bookings created in each window. */
export async function getBookingMixByPeriod(): Promise<ByPeriod<BookingMixEntry[]>> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);
  return forEachPeriod(bookingMixForDays);
}

// --- Moderation, per window --------------------------------------------------

async function moderationForDays(days: number): Promise<ModerationStats> {
  const rows = await prisma.$queryRaw<ModerationStatsRow[]>`
    SELECT
      count(*)::int AS "totalListings",
      count(*) FILTER (WHERE verification_status = 'verified')::int AS "verifiedCount",
      count(*) FILTER (WHERE verification_status = 'pending')::int AS "pendingCount",
      avg(extract(epoch FROM (verified_at - created_at)))
        FILTER (WHERE verification_status = 'verified' AND verified_at IS NOT NULL)::float8 AS "avgTurnaroundSeconds"
    FROM (
      SELECT verification_status, verified_at, created_at
      FROM attractions
      WHERE deleted_at IS NULL AND created_at >= now() - (${days}::int * interval '1 day')
      UNION ALL
      SELECT verification_status, verified_at, created_at
      FROM restaurants
      WHERE deleted_at IS NULL AND created_at >= now() - (${days}::int * interval '1 day')
    ) listings
  `;
  return toModerationStats(rows[0]!);
}

/** Verification stats for listings created in each window (the header pill stays all-time). */
export async function getModerationByPeriod(): Promise<ByPeriod<ModerationStats>> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);
  return forEachPeriod(moderationForDays);
}

// --- Destination ranking -----------------------------------------------------

interface DestinationUsageRow {
  location: string;
  tripCount: number;
}

interface MergedDestination extends DestinationUsageRow {
  /** The `normalizeDestination` key the group was merged on. */
  key: string;
}

/**
 * The spelling to show for one merged group. Each raw string is first reduced
 * to its display label (`destinationLabel`: "Da Nang, Vietnam" -> "Da Nang"),
 * then the label with the most trips behind it wins. Ties are broken the same
 * way every time instead of by whichever row the database returned first: a
 * capitalised spelling beats a lowercase one, then plain code-unit order (not
 * `localeCompare`, which would put "Da nang" before "Da Nang").
 */
function pickLabel(votes: Map<string, number>): string {
  const capitalised = (label: string) => /^\p{Lu}/u.test(label);
  return [...votes.entries()].sort(
    ([labelA, votesA], [labelB, votesB]) =>
      votesB - votesA ||
      Number(capitalised(labelB)) - Number(capitalised(labelA)) ||
      (labelA < labelB ? -1 : labelA > labelB ? 1 : 0),
  )[0]![0];
}

/**
 * Merges raw location groups that share a `normalizeDestination` key (e.g.
 * "Saigon", "Ho Chi Minh City" and "Ho Chi Minh City, Vietnam" trips all
 * become one "Ho Chi Minh City" row), summing their counts. The displayed
 * label is not the normalized key (just a matching key, not display text) but
 * the most common display spelling — see `pickLabel`. Rows are case-preserving
 * (`trim(location)`, not lowercased) specifically so that popularity contest is
 * meaningful. Each result carries its `key`, so callers (the Featured check)
 * never have to re-derive it from the label.
 */
function mergeByNormalizedDestination(
  rows: DestinationUsageRow[],
): MergedDestination[] {
  const merged = new Map<
    string,
    { tripCount: number; labelVotes: Map<string, number> }
  >();

  for (const row of rows) {
    const key = normalizeDestination(row.location);
    const group = merged.get(key) ?? {
      tripCount: 0,
      labelVotes: new Map<string, number>(),
    };
    group.tripCount += row.tripCount;
    const label = destinationLabel(row.location);
    group.labelVotes.set(
      label,
      (group.labelVotes.get(label) ?? 0) + row.tripCount,
    );
    merged.set(key, group);
  }

  return [...merged.entries()]
    .map(([key, { tripCount, labelVotes }]) => ({
      key,
      location: pickLabel(labelVotes),
      tripCount,
    }))
    .sort(
      (a, b) =>
        b.tripCount - a.tripCount || a.location.localeCompare(b.location),
    );
}

function destinationUsageForDays(days: number): Promise<DestinationUsageRow[]> {
  return prisma.$queryRaw<DestinationUsageRow[]>`
    SELECT trim(location) AS location, count(*)::int AS "tripCount"
    FROM trips
    WHERE created_at >= now() - (${days}::int * interval '1 day')
    GROUP BY 1
  `;
}

/**
 * Usage-ranked by `Trip.location` per window (trips created in the last 30 /
 * 90 / 365 days), merged across spellings that share a `normalizeDestination`
 * key, top 6, and cross-referenced against `CuratedCollection.scopeValue` for a
 * "Featured" badge via the same normalizer. `CuratedCollection` has no FK to
 * `Trip`/`TripStop` at all, so that cross-reference is always a fuzzy string
 * match, not a real join. A window with no trips is an honest empty list; only
 * a fresh environment with no trips in the whole year falls back to the
 * editorial `CuratedCollection` ranking (labelled "Featured Destinations" by
 * the caller) for every window.
 */
export async function getDestinationRankingByPeriod(): Promise<ByPeriod<DestinationRanking>> {
  "use cache";
  cacheLife(DASHBOARD_CACHE_LIFE);

  const [usage, collections] = await Promise.all([
    forEachPeriod(destinationUsageForDays),
    prisma.curatedCollection.findMany({
      where: { isDestination: true },
      orderBy: { sortOrder: "asc" },
      select: { title: true, scopeValue: true },
    }),
  ]);

  if (usage.year.length === 0) {
    const editorial: DestinationRanking = {
      mode: "editorial",
      items: collections.slice(0, 6).map((c) => ({ title: c.title })),
    };
    return { month: editorial, quarter: editorial, year: editorial };
  }

  const featuredScopes = new Set(
    collections.map((c) => normalizeDestination(c.scopeValue)),
  );
  const toRanking = (rows: DestinationUsageRow[]): DestinationRanking => ({
    mode: "usage",
    items: mergeByNormalizedDestination(rows)
      .slice(0, 6)
      .map((row) => ({
        location: row.location,
        tripCount: row.tripCount,
        featured: featuredScopes.has(row.key),
      })),
  });

  return {
    month: toRanking(usage.month),
    quarter: toRanking(usage.quarter),
    year: toRanking(usage.year),
  };
}

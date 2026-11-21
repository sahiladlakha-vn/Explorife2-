import type { PerformancePeriod } from "./periods";

// Plain data shapes for /admin/dashboard. They live here (not in
// lib/server/admin-dashboard.ts, which is `server-only`) so Client Components,
// the dev-preview fixtures and the tests can import them freely.

/** Dates are Vietnam calendar days (Asia/Ho_Chi_Minh), as `YYYY-MM-DD`. */
export type DayString = string;

export interface TripsInProgress {
  activeCount: number;
  /** Trips whose endDate is before today (Vietnam calendar date). */
  completedCount: number;
  totalCount: number;
  /** Active trips as a whole-number percentage of all trips. */
  percentage: number;
  /** Completed trips as a whole-number percentage of all trips. */
  completedPercentage: number;
}

export interface UpcomingBookingCoverage {
  upcomingCount: number;
  withBookingCount: number;
  percentage: number;
}

export interface ModerationStats {
  totalListings: number;
  verifiedCount: number;
  pendingCount: number;
  percentage: number;
  avgTurnaroundHours: number | null;
}

export interface BookingValueDay {
  day: DayString;
  count: number;
  amountVnd: number;
}

export interface BookingValueSummary {
  /** Lifetime sum of paid bookings. */
  paidVnd: number;
  paidCount: number;
  /** Paid bookings per Vietnam day for the last 14 days, oldest first, zero-filled. */
  daily: BookingValueDay[];
  /** Paid total for the last 7 days of `daily`. */
  last7Vnd: number;
  /** Paid total for the 7 days before that. */
  prev7Vnd: number;
  /** Whole-number % change last7 vs prev7; null when prev7 is 0 (no baseline). */
  changePercent: number | null;
}

export interface BookingVelocityDay {
  day: DayString;
  count: number;
}

export interface BookingVelocity {
  /** All bookings (any status) per Vietnam day for the last 14 days, oldest first, zero-filled. */
  daily: BookingVelocityDay[];
  total: number;
}

export interface BookingFunnel {
  toBook: number;
  booked: number;
  paid: number;
}

export interface WeekTrip {
  id: string;
  name: string;
  location: string;
  startDate: DayString;
  endDate: DayString;
}

export interface UpcomingWeek {
  /** Monday of the current Vietnam week. */
  weekStart: DayString;
  /** Today in Vietnam. */
  today: DayString;
  /** Trips overlapping the week, earliest first. */
  trips: WeekTrip[];
  /** First trip starting after this week, if any. */
  nextTrip: WeekTrip | null;
}

export interface RecentBookingItem {
  id: string;
  tripName: string;
  bookingType: string;
  amountVnd: number | null;
  status: string;
  createdAt: string;
}

export interface BookingMixEntry {
  bookingType: string;
  count: number;
  amountVnd: number;
}

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

export type ByPeriod<T> = Record<PerformancePeriod, T>;

import type { DayString } from "./types";

// Pure helpers for the Booking Value / Velocity cards. Days arrive from SQL as
// Vietnam calendar days (`YYYY-MM-DD`); labelling them in UTC is exact because
// the string already *is* the calendar date — no time zone is applied again.

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;

function parseDay(day: DayString): Date {
  return new Date(`${day}T00:00:00Z`);
}

/** "2026-11-21" -> "Sat". */
export function weekdayShort(day: DayString): string {
  return WEEKDAYS[parseDay(day).getUTCDay()]!;
}

/** "2026-11-21" -> "Nov 21". */
export function monthDayShort(day: DayString): string {
  const date = parseDay(day);
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCDate()}`;
}

/**
 * Whole-number % change from `previous` to `current`. Null when there is no
 * baseline (`previous` is 0): a percentage of zero is undefined, and "+∞%"
 * would be noise — the UI shows "New" instead.
 */
export function percentChange(
  current: number,
  previous: number,
): number | null {
  if (previous === 0) return null;
  return Math.round(((current - previous) / previous) * 100);
}

const sum = (values: number[]) => values.reduce((total, v) => total + v, 0);

/** Sums the last 7 entries and the 7 before them (oldest-first input). */
export function lastAndPreviousSevenDays(values: number[]): {
  last7: number;
  prev7: number;
} {
  return {
    last7: sum(values.slice(-7)),
    prev7: sum(values.slice(-14, -7)),
  };
}

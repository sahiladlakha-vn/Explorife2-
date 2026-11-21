import { weekdayShort } from "./booking-trends";
import type { DayString, WeekTrip } from "./types";

// Layout maths for the Upcoming Trips week strip. Everything is calendar-day
// arithmetic on `YYYY-MM-DD` strings (via Date.UTC) — never the current time,
// so a static dev-preview fixture renders identically on every visit.

const DAY_MS = 86_400_000;

function toUtcMs(day: DayString): number {
  const [year, month, date] = day.split("-").map(Number);
  return Date.UTC(year!, month! - 1, date!);
}

/** Whole days from `from` to `to` (negative when `to` is earlier). */
export function dayDiff(from: DayString, to: DayString): number {
  return Math.round((toUtcMs(to) - toUtcMs(from)) / DAY_MS);
}

export function addDays(day: DayString, days: number): DayString {
  return new Date(toUtcMs(day) + days * DAY_MS).toISOString().slice(0, 10);
}

export interface WeekStripDay {
  date: DayString;
  weekday: string;
  dayOfMonth: number;
  isToday: boolean;
}

/** The seven columns of the strip, Monday first. */
export function buildWeekDays(
  weekStart: DayString,
  today: DayString,
): WeekStripDay[] {
  return Array.from({ length: 7 }, (_, index) => {
    const date = addDays(weekStart, index);
    return {
      date,
      weekday: weekdayShort(date),
      dayOfMonth: Number(date.slice(8, 10)),
      isToday: date === today,
    };
  });
}

export interface WeekStripSpan {
  id: string;
  name: string;
  location: string;
  /** 1-based grid columns, inclusive, clipped to the week. */
  startCol: number;
  endCol: number;
  /** 0-based row; overlapping trips stack in separate lanes. */
  lane: number;
  /** The trip started before this week / continues after it. */
  continuesBefore: boolean;
  continuesAfter: boolean;
}

/**
 * Places each trip across the columns between its start and end dates, clipped
 * to the week, and stacks overlapping trips into lanes (first lane that is
 * free). Trips entirely outside the week are dropped.
 */
export function layoutWeekSpans(
  trips: WeekTrip[],
  weekStart: DayString,
): { spans: WeekStripSpan[]; laneCount: number } {
  const laneEnds: number[] = [];
  const spans: WeekStripSpan[] = [];

  const ordered = [...trips].sort(
    (a, b) =>
      a.startDate.localeCompare(b.startDate) ||
      a.endDate.localeCompare(b.endDate) ||
      a.id.localeCompare(b.id),
  );

  for (const trip of ordered) {
    const rawStart = dayDiff(weekStart, trip.startDate);
    const rawEnd = dayDiff(weekStart, trip.endDate);
    if (rawEnd < 0 || rawStart > 6) continue;

    const startCol = Math.max(rawStart, 0) + 1;
    // A trip whose end precedes its start (bad data) still gets one cell.
    const endCol = Math.max(Math.min(rawEnd, 6) + 1, startCol);

    let lane = laneEnds.findIndex((end) => end < startCol);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(endCol);
    } else {
      laneEnds[lane] = endCol;
    }

    spans.push({
      id: trip.id,
      name: trip.name,
      location: trip.location,
      startCol,
      endCol,
      lane,
      continuesBefore: rawStart < 0,
      continuesAfter: rawEnd > 6,
    });
  }

  return { spans, laneCount: laneEnds.length };
}

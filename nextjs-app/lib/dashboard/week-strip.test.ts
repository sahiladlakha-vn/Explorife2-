import { describe, expect, it } from "vitest";
import {
  addDays,
  buildWeekDays,
  dayDiff,
  layoutWeekSpans,
} from "./week-strip";
import type { WeekTrip } from "./types";

// Week under test: Monday 2026-11-16 .. Sunday 2026-11-22.
const WEEK = "2026-11-16";

const trip = (id: string, startDate: string, endDate: string): WeekTrip => ({
  id,
  name: `Trip ${id}`,
  location: "Somewhere",
  startDate,
  endDate,
});

describe("calendar arithmetic", () => {
  it("adds days across a month boundary", () => {
    expect(addDays("2026-11-28", 5)).toBe("2026-12-03");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("counts whole days between two dates, negative when going back", () => {
    expect(dayDiff(WEEK, "2026-11-22")).toBe(6);
    expect(dayDiff(WEEK, "2026-11-14")).toBe(-2);
  });
});

describe("buildWeekDays", () => {
  it("returns seven columns, Monday first, flagging only today", () => {
    const days = buildWeekDays(WEEK, "2026-11-19");
    expect(days.map((d) => d.weekday)).toEqual([
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);
    expect(days.map((d) => d.dayOfMonth)).toEqual([16, 17, 18, 19, 20, 21, 22]);
    expect(days.filter((d) => d.isToday).map((d) => d.weekday)).toEqual(["Thu"]);
  });

  it("flags nothing when today is outside the week", () => {
    expect(buildWeekDays(WEEK, "2026-12-01").some((d) => d.isToday)).toBe(false);
  });
});

describe("layoutWeekSpans", () => {
  it("places a trip across the columns between its start and end dates", () => {
    const { spans } = layoutWeekSpans([trip("a", "2026-11-17", "2026-11-19")], WEEK);
    expect(spans).toEqual([
      expect.objectContaining({
        id: "a",
        startCol: 2,
        endCol: 4,
        lane: 0,
        continuesBefore: false,
        continuesAfter: false,
      }),
    ]);
  });

  it("clips trips that started before or run past the week and says so", () => {
    const { spans } = layoutWeekSpans(
      [
        trip("before", "2026-11-12", "2026-11-17"),
        trip("after", "2026-11-20", "2026-11-30"),
      ],
      WEEK,
    );
    const before = spans.find((s) => s.id === "before")!;
    const after = spans.find((s) => s.id === "after")!;
    expect([before.startCol, before.endCol, before.continuesBefore]).toEqual([1, 2, true]);
    expect([after.startCol, after.endCol, after.continuesAfter]).toEqual([5, 7, true]);
  });

  it("stacks overlapping trips into lanes and reuses a lane once it is free", () => {
    const { spans, laneCount } = layoutWeekSpans(
      [
        trip("a", "2026-11-16", "2026-11-18"), // cols 1-3
        trip("b", "2026-11-17", "2026-11-19"), // cols 2-4, overlaps a
        trip("c", "2026-11-19", "2026-11-20"), // cols 4-5, fits lane 0 again
      ],
      WEEK,
    );
    const lane = (id: string) => spans.find((s) => s.id === id)!.lane;
    expect([lane("a"), lane("b"), lane("c")]).toEqual([0, 1, 0]);
    expect(laneCount).toBe(2);
  });

  it("drops trips entirely outside the week", () => {
    const { spans, laneCount } = layoutWeekSpans(
      [trip("past", "2026-11-01", "2026-11-15"), trip("future", "2026-11-23", "2026-11-25")],
      WEEK,
    );
    expect(spans).toEqual([]);
    expect(laneCount).toBe(0);
  });

  it("gives a trip whose end precedes its start a single cell instead of a negative span", () => {
    const { spans } = layoutWeekSpans([trip("bad", "2026-11-18", "2026-11-17")], WEEK);
    expect([spans[0]!.startCol, spans[0]!.endCol]).toEqual([3, 3]);
  });

  it("does not depend on the order trips are passed in", () => {
    const trips = [
      trip("a", "2026-11-16", "2026-11-18"),
      trip("b", "2026-11-17", "2026-11-19"),
    ];
    expect(layoutWeekSpans([...trips].reverse(), WEEK)).toEqual(
      layoutWeekSpans(trips, WEEK),
    );
  });
});

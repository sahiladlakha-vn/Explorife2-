import { describe, expect, it } from "vitest";
import {
  lastAndPreviousSevenDays,
  monthDayShort,
  percentChange,
  weekdayShort,
} from "./booking-trends";

describe("weekdayShort / monthDayShort", () => {
  it("names the weekday of a calendar day", () => {
    expect(weekdayShort("2026-11-16")).toBe("Mon");
    expect(weekdayShort("2026-11-21")).toBe("Sat");
    expect(weekdayShort("2026-11-22")).toBe("Sun");
  });

  it("formats a day as 'Mon D' with no leading zero", () => {
    expect(monthDayShort("2026-11-21")).toBe("Nov 21");
    expect(monthDayShort("2026-01-05")).toBe("Jan 5");
    expect(monthDayShort("2026-12-31")).toBe("Dec 31");
  });
});

describe("percentChange", () => {
  it("returns the whole-number change, up or down", () => {
    expect(percentChange(150, 100)).toBe(50);
    expect(percentChange(50, 100)).toBe(-50);
    expect(percentChange(0, 100)).toBe(-100);
  });

  it("rounds to the nearest whole percent", () => {
    expect(percentChange(101, 100)).toBe(1);
    expect(percentChange(1, 3)).toBe(-67);
  });

  it("returns null when there is no baseline rather than dividing by zero", () => {
    expect(percentChange(100, 0)).toBeNull();
    expect(percentChange(0, 0)).toBeNull();
  });
});

describe("lastAndPreviousSevenDays", () => {
  it("splits an oldest-first 14-day series into the two weeks", () => {
    const values = Array.from({ length: 14 }, (_, i) => i + 1);
    expect(lastAndPreviousSevenDays(values)).toEqual({ last7: 77, prev7: 28 });
  });

  it("treats a short series as all 'last' with no previous week", () => {
    expect(lastAndPreviousSevenDays([1, 2, 3])).toEqual({ last7: 6, prev7: 0 });
    expect(lastAndPreviousSevenDays([])).toEqual({ last7: 0, prev7: 0 });
  });
});

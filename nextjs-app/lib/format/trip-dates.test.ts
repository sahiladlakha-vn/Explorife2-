import { describe, it, expect } from "vitest";
import { formatTripDateRange } from "./trip-dates";

describe("formatTripDateRange", () => {
  it("formats a same-month range", () => {
    expect(
      formatTripDateRange(new Date("2026-08-12T00:00:00.000Z"), new Date("2026-08-22T00:00:00.000Z")),
    ).toBe("Aug 12 – 22 · 10 nights");
  });

  it("formats a cross-month range", () => {
    expect(
      formatTripDateRange(new Date("2026-08-28T00:00:00.000Z"), new Date("2026-09-02T00:00:00.000Z")),
    ).toBe("Aug 28 – Sep 2 · 5 nights");
  });

  it("formats a cross-year range", () => {
    expect(
      formatTripDateRange(new Date("2026-12-29T00:00:00.000Z"), new Date("2027-01-02T00:00:00.000Z")),
    ).toBe("Dec 29, 2026 – Jan 2, 2027 · 4 nights");
  });

  it("uses singular 'night' for a 1-night trip", () => {
    expect(
      formatTripDateRange(new Date("2026-08-12T00:00:00.000Z"), new Date("2026-08-13T00:00:00.000Z")),
    ).toBe("Aug 12 – 13 · 1 night");
  });
});

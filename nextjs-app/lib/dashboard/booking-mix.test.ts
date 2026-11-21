import { describe, expect, it } from "vitest";
import { fillBookingMix } from "./booking-mix";

describe("fillBookingMix", () => {
  it("returns the four known types, zero-filled, when there is no data", () => {
    expect(fillBookingMix([])).toEqual([
      { bookingType: "flight", count: 0, amountVnd: 0 },
      { bookingType: "stay", count: 0, amountVnd: 0 },
      { bookingType: "activity", count: 0, amountVnd: 0 },
      { bookingType: "transport", count: 0, amountVnd: 0 },
    ]);
  });

  it("keeps real rows in the canonical order and zero-fills only the missing ones", () => {
    const result = fillBookingMix([
      { bookingType: "transport", count: 5, amountVnd: 500 },
      { bookingType: "flight", count: 2, amountVnd: 900 },
    ]);
    expect(result.map((r) => r.bookingType)).toEqual(["flight", "stay", "activity", "transport"]);
    expect(result[0]).toEqual({ bookingType: "flight", count: 2, amountVnd: 900 });
    expect(result[1]).toEqual({ bookingType: "stay", count: 0, amountVnd: 0 });
    expect(result[3]).toEqual({ bookingType: "transport", count: 5, amountVnd: 500 });
  });

  it("appends unexpected booking types after the known ones, most frequent first", () => {
    const result = fillBookingMix([
      { bookingType: "visa", count: 1, amountVnd: 10 },
      { bookingType: "insurance", count: 4, amountVnd: 40 },
    ]);
    expect(result.map((r) => r.bookingType)).toEqual([
      "flight",
      "stay",
      "activity",
      "transport",
      "insurance",
      "visa",
    ]);
  });
});

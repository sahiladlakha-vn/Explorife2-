import { describe, it, expect } from "vitest";
import { expiryAlertFor, formatDocumentDate } from "./document-alerts";

/** `m` is 1-based here purely for readability at call sites below. */
function utcDate(y: number, m: number, d: number): Date {
  return new Date(Date.UTC(y, m - 1, d));
}

describe("formatDocumentDate", () => {
  it("formats as 'Mon D, YYYY'", () => {
    expect(formatDocumentDate(utcDate(2026, 8, 12))).toBe("Aug 12, 2026");
  });

  it("renders single-digit days without a leading zero", () => {
    expect(formatDocumentDate(utcDate(2027, 1, 5))).toBe("Jan 5, 2027");
  });
});

describe("expiryAlertFor", () => {
  const trip = { startDate: utcDate(2026, 6, 10), endDate: utcDate(2026, 6, 20) };

  it("returns null when the document has no expiry", () => {
    expect(expiryAlertFor({ type: "visa", expiresOn: null }, trip)).toBeNull();
  });

  it("returns null for a non-passport expiring outside the trip window", () => {
    expect(expiryAlertFor({ type: "visa", expiresOn: utcDate(2027, 1, 1) }, trip)).toBeNull();
  });

  it("flags a non-passport document expiring on the trip's start date (inclusive)", () => {
    expect(expiryAlertFor({ type: "ticket", expiresOn: trip.startDate }, trip)).toEqual({
      label: "ENDS MID-TRIP",
      tone: "warn",
    });
  });

  it("flags a non-passport document expiring on the trip's end date (inclusive)", () => {
    expect(expiryAlertFor({ type: "reservation", expiresOn: trip.endDate }, trip)).toEqual({
      label: "ENDS MID-TRIP",
      tone: "warn",
    });
  });

  it("flags a passport expiring less than 6 months after the trip's end date", () => {
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2026, 10, 1) }, trip)).toEqual({
      label: "6-MO RULE",
      tone: "critical",
    });
  });

  it("does not flag a passport expiring exactly 6 months after the trip's end date", () => {
    // Trip ends 2026-06-20; 6 months later is 2026-12-20 exactly, which
    // clears the bar (the source uses a strict `<`) and is also well outside
    // the trip's own window, so there's no fallthrough to the warn case.
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2026, 12, 20) }, trip)).toBeNull();
  });

  it("flags a passport expiring one day before the 6-month boundary", () => {
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2026, 12, 19) }, trip)).toEqual({
      label: "6-MO RULE",
      tone: "critical",
    });
  });

  it("returns null for a passport expiring well beyond the 6-month boundary", () => {
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2028, 6, 20) }, trip)).toBeNull();
  });

  it("rolls the 6-month boundary over into the following year", () => {
    const longTrip = { startDate: utcDate(2026, 10, 1), endDate: utcDate(2026, 10, 15) };
    // 6 months after Oct 15, 2026 is Apr 15, 2027.
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2027, 4, 10) }, longTrip)).toEqual({
      label: "6-MO RULE",
      tone: "critical",
    });
    expect(expiryAlertFor({ type: "passport", expiresOn: utcDate(2027, 4, 20) }, longTrip)).toBeNull();
  });
});

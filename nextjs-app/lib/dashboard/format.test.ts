import { describe, expect, it } from "vitest";
import { formatTurnaround, vietnamDayShort } from "./format";

describe("vietnamDayShort", () => {
  it("names the Vietnam calendar day of an instant", () => {
    expect(vietnamDayShort("2026-11-21T03:00:00Z")).toBe("Nov 21");
  });

  it("rolls late-evening UTC over to the next day in Vietnam (UTC+7)", () => {
    // 20:00 UTC is 03:00 the next morning in Ho Chi Minh City.
    expect(vietnamDayShort("2026-11-21T20:00:00Z")).toBe("Nov 22");
    // 16:59 UTC is still 23:59 the same day.
    expect(vietnamDayShort("2026-11-21T16:59:00Z")).toBe("Nov 21");
  });
});

describe("formatTurnaround", () => {
  it("shows minutes under an hour, never 0", () => {
    expect(formatTurnaround(0.75)).toBe("45 min");
    expect(formatTurnaround(0.001)).toBe("1 min");
  });

  it("shows hours with one decimal under two days, dropping a trailing .0", () => {
    expect(formatTurnaround(4.3)).toBe("4.3 h");
    expect(formatTurnaround(12)).toBe("12 h");
    expect(formatTurnaround(47.96)).toBe("48 h");
  });

  it("switches to days from 48 hours", () => {
    expect(formatTurnaround(60)).toBe("2.5 d");
    expect(formatTurnaround(72)).toBe("3 d");
  });
});

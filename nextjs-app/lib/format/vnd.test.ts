import { describe, expect, it } from "vitest";
import { formatCompactVnd } from "./vnd";

describe("formatCompactVnd", () => {
  it("formats billions with the 'tỷ' suffix", () => {
    expect(formatCompactVnd(1_200_000_000)).toBe("1,2 tỷ");
    expect(formatCompactVnd(12_000_000_000)).toBe("12 tỷ");
  });

  it("formats millions with the 'tr' suffix", () => {
    expect(formatCompactVnd(284_000_000)).toBe("284 tr");
    expect(formatCompactVnd(1_500_000)).toBe("1,5 tr");
  });

  it("formats thousands with the 'n' suffix", () => {
    expect(formatCompactVnd(950_000)).toBe("950 n");
    expect(formatCompactVnd(1_000)).toBe("1 n");
  });

  it("returns the plain number below one thousand", () => {
    expect(formatCompactVnd(500)).toBe("500");
    expect(formatCompactVnd(0)).toBe("0");
  });

  it("drops a trailing ',0' rather than showing a meaningless decimal", () => {
    expect(formatCompactVnd(2_000_000_000)).toBe("2 tỷ");
    expect(formatCompactVnd(3_000_000)).toBe("3 tr");
  });

  it("preserves a negative sign", () => {
    expect(formatCompactVnd(-1_200_000_000)).toBe("-1,2 tỷ");
  });
});

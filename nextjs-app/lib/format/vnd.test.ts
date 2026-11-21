import { describe, expect, it } from "vitest";
import { formatCompactVnd } from "./vnd";

describe("formatCompactVnd", () => {
  it("formats billions as 'Tỷ đ' with a decimal comma", () => {
    expect(formatCompactVnd(1_200_000_000)).toBe("1,2 Tỷ đ");
    expect(formatCompactVnd(12_000_000_000)).toBe("12 Tỷ đ");
  });

  it("formats millions as 'tr đ'", () => {
    expect(formatCompactVnd(284_000_000)).toBe("284 tr đ");
    expect(formatCompactVnd(1_500_000)).toBe("1,5 tr đ");
  });

  it("shows the full amount, grouped with dots, below a million", () => {
    expect(formatCompactVnd(950_000)).toBe("950.000 đ");
    expect(formatCompactVnd(1_000)).toBe("1.000 đ");
    expect(formatCompactVnd(500)).toBe("500 đ");
    expect(formatCompactVnd(0)).toBe("0 đ");
  });

  it("drops a trailing ',0' rather than showing a meaningless decimal", () => {
    expect(formatCompactVnd(2_000_000_000)).toBe("2 Tỷ đ");
    expect(formatCompactVnd(3_000_000)).toBe("3 tr đ");
  });

  it("rolls 999.96 tr up to 1 Tỷ instead of printing '1000 tr'", () => {
    expect(formatCompactVnd(999_960_000)).toBe("1 Tỷ đ");
    expect(formatCompactVnd(999_940_000)).toBe("999,9 tr đ");
  });

  it("preserves a negative sign in every tier", () => {
    expect(formatCompactVnd(-1_200_000_000)).toBe("-1,2 Tỷ đ");
    expect(formatCompactVnd(-284_000_000)).toBe("-284 tr đ");
    expect(formatCompactVnd(-950_000)).toBe("-950.000 đ");
  });
});

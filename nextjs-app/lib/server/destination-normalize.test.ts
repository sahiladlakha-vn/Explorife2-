import { describe, expect, it } from "vitest";
import { normalizeDestination } from "./destination-normalize";

describe("normalizeDestination", () => {
  it("lowercases and trims surrounding whitespace", () => {
    expect(normalizeDestination("  Sapa  ")).toBe("sapa");
  });

  it("strips Vietnamese diacritics, including đ which doesn't decompose under NFD", () => {
    expect(normalizeDestination("Đà Nẵng")).toBe("da nang");
    expect(normalizeDestination("Hạ Long")).toBe("ha long");
  });

  it("collapses hyphens and repeated whitespace into single spaces", () => {
    expect(normalizeDestination("da---nang")).toBe("da nang");
    expect(normalizeDestination("Da   Nang")).toBe("da nang");
  });

  it("is case-insensitive", () => {
    expect(normalizeDestination("DA NANG")).toBe("da nang");
  });

  it('maps the fused "Halong Bay" spelling to "ha long bay"', () => {
    expect(normalizeDestination("Halong Bay")).toBe("ha long bay");
    expect(normalizeDestination("Ha Long Bay")).toBe("ha long bay");
  });

  it('maps "Saigon" and "HCMC" to "ho chi minh city"', () => {
    expect(normalizeDestination("Saigon")).toBe("ho chi minh city");
    expect(normalizeDestination("HCMC")).toBe("ho chi minh city");
    expect(normalizeDestination("Ho Chi Minh City")).toBe("ho chi minh city");
  });

  it('maps "Sai Gon" (space-separated) and its accented form to "ho chi minh city"', () => {
    expect(normalizeDestination("Sai Gon")).toBe("ho chi minh city");
    expect(normalizeDestination("Sài Gòn")).toBe("ho chi minh city");
  });

  it('strips a leading "tp"/"thanh pho" city prefix before the alias lookup', () => {
    expect(normalizeDestination("TP HCM")).toBe("ho chi minh city");
    expect(normalizeDestination("TPHCM")).toBe("ho chi minh city");
    expect(normalizeDestination("TP.HCM")).toBe("ho chi minh city");
    expect(normalizeDestination("TP Ho Chi Minh")).toBe("ho chi minh city");
    expect(normalizeDestination("Thanh Pho Ho Chi Minh")).toBe("ho chi minh city");
  });

  it('unifies "da nang" and "Đà Nẵng" via diacritic-stripping alone, with no alias entry needed', () => {
    expect(normalizeDestination("da nang")).toBe(normalizeDestination("Đà Nẵng"));
  });
});

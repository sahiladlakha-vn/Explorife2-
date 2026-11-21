import { describe, expect, it } from "vitest";
import { destinationLabel, normalizeDestination } from "./destination-normalize";

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

describe("normalizeDestination: geocoder strings and typed text", () => {
  it("compares on the place name, ignoring the province and country a geocoder appends", () => {
    expect(normalizeDestination("Da Nang, Vietnam")).toBe("da nang");
    expect(normalizeDestination("Hội An, An Giang, Vietnam")).toBe("hoi an");
    expect(normalizeDestination("Đà Lạt, Lâm Đồng, Vietnam")).toBe("da lat");
    expect(normalizeDestination("Mũi Né, Lâm Đồng, Vietnam")).toBe("mui ne");
  });

  it("puts a geocoder string and the typed spellings of the same city on one key", () => {
    const key = normalizeDestination("Da Nang, Vietnam");
    for (const typed of ["da nang", "Da nang", "DA NANG", "Đà Nẵng", "da-nang"]) {
      expect(normalizeDestination(typed), typed).toBe(key);
    }
    expect(normalizeDestination("hoi an")).toBe(
      normalizeDestination("Hội An, An Giang, Vietnam"),
    );
  });

  it("accepts every spelling of Vietnam as the country", () => {
    for (const country of ["Vietnam", "VIETNAM", "Viet Nam", "Việt Nam", "  vietnam  "]) {
      expect(normalizeDestination(`Hanoi, ${country}`), country).toBe("hanoi");
    }
  });

  it("still applies the aliases and the tp prefix to the place name", () => {
    expect(normalizeDestination("Ho Chi Minh City, Vietnam")).toBe("ho chi minh city");
    expect(normalizeDestination("Saigon, Vietnam")).toBe("ho chi minh city");
    expect(normalizeDestination("TP.HCM, Vietnam")).toBe("ho chi minh city");
    expect(normalizeDestination("Halong Bay, Quảng Ninh, Vietnam")).toBe("ha long bay");
  });

  it("keeps any other country in the key and does not apply the Vietnam aliases", () => {
    expect(normalizeDestination("Hamburg, Germany")).toBe("hamburg, germany");
    expect(normalizeDestination("Dalian Shi, Liaoning, China")).toBe("dalian shi, china");
    expect(
      normalizeDestination("Roadside of Catterline, Aberdeenshire, Scotland, United Kingdom"),
    ).toBe("roadside of catterline, united kingdom");
  });

  it('never folds "Saigon" in Indonesia into Ho Chi Minh City', () => {
    const indonesian = "Saigon, 78132, Pontianak Timur, Pontianak, West Kalimantan, Indonesia";
    expect(normalizeDestination(indonesian)).toBe("saigon, indonesia");
    expect(normalizeDestination(indonesian)).not.toBe(normalizeDestination("Saigon"));
    expect(normalizeDestination(indonesian)).not.toBe(
      normalizeDestination("Ho Chi Minh City, Vietnam"),
    );
  });

  it("ignores the middle parts of a foreign string, and tells countries apart", () => {
    expect(normalizeDestination("Hamburg, Hamburg, Germany")).toBe(
      normalizeDestination("Hamburg, Germany"),
    );
    expect(normalizeDestination("Paris, France")).not.toBe(
      normalizeDestination("Paris, Texas, United States"),
    );
  });

  it("leaves typed text with no country part apart from a geocoded foreign place (a safe miss)", () => {
    expect(normalizeDestination("hamburg")).not.toBe(normalizeDestination("Hamburg, Germany"));
    expect(normalizeDestination("Hội An, Quảng Nam")).not.toBe(normalizeDestination("hoi an"));
  });

  it("copes with stray commas and whitespace", () => {
    expect(normalizeDestination("")).toBe("");
    expect(normalizeDestination("   ")).toBe("");
    expect(normalizeDestination(" , ")).toBe("");
    expect(normalizeDestination("Hanoi,")).toBe("hanoi");
    expect(normalizeDestination(",Hanoi")).toBe("hanoi");
    expect(normalizeDestination("  Da Nang ,  Vietnam ")).toBe("da nang");
  });
});

describe("normalizeDestination: Hanoi", () => {
  it('maps "Hà Nội" and "Ha Noi" onto the one-word "hanoi" the featured destination uses', () => {
    for (const spelling of ["Hanoi", "Hà Nội", "Ha Noi", "HA-NOI", "ha noi"]) {
      expect(normalizeDestination(spelling), spelling).toBe("hanoi");
    }
  });

  it("does so for geocoder strings too", () => {
    expect(normalizeDestination("Hà Nội, Việt Nam")).toBe("hanoi");
    expect(normalizeDestination("Hanoi, Viet Nam")).toBe("hanoi");
  });
});

describe("destinationLabel", () => {
  it("shows just the place name for a Vietnamese destination", () => {
    expect(destinationLabel("Da Nang, Vietnam")).toBe("Da Nang");
    expect(destinationLabel("Hội An, An Giang, Vietnam")).toBe("Hội An");
    expect(destinationLabel("Hà Nội, Việt Nam")).toBe("Hà Nội");
  });

  it("keeps the country for any other country, and drops the parts in between", () => {
    expect(destinationLabel("Hamburg, Germany")).toBe("Hamburg, Germany");
    expect(destinationLabel("Dalian Shi, Liaoning, China")).toBe("Dalian Shi, China");
    expect(
      destinationLabel("Saigon, 78132, Pontianak Timur, Pontianak, West Kalimantan, Indonesia"),
    ).toBe("Saigon, Indonesia");
  });

  it("leaves a single typed part as typed, trimmed, with its original case", () => {
    expect(destinationLabel("  da nang ")).toBe("da nang");
    expect(destinationLabel("Sapa")).toBe("Sapa");
    expect(destinationLabel("Hanoi,")).toBe("Hanoi");
    expect(destinationLabel("  ")).toBe("");
  });

  it("always agrees with normalizeDestination", () => {
    for (const raw of [
      "Da Nang, Vietnam",
      "da nang",
      "Hội An, An Giang, Vietnam",
      "TP.HCM, Vietnam",
      "Saigon",
      "Hà Nội, Việt Nam",
      "Hamburg, Germany",
      "Dalian Shi, Liaoning, China",
      "Saigon, 78132, Pontianak Timur, Pontianak, West Kalimantan, Indonesia",
      "Roadside of Catterline, Aberdeenshire, Scotland, United Kingdom",
      "Hanoi,",
      "",
    ]) {
      expect(normalizeDestination(destinationLabel(raw)), raw).toBe(normalizeDestination(raw));
    }
  });
});

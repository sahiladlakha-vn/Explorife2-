import { describe, expect, it } from "vitest";
import { pickDisplayName } from "./display-name";

describe("pickDisplayName", () => {
  it("prefers the display name over the plain name", () => {
    expect(pickDisplayName({ displayName: "Linh", name: "Nguyen Thi Linh" })).toBe("Linh");
  });

  it("falls back to the plain name when there is no display name", () => {
    expect(pickDisplayName({ displayName: null, name: "Nguyen Thi Linh" })).toBe(
      "Nguyen Thi Linh",
    );
  });

  it("trims whitespace and treats blank values as missing", () => {
    expect(pickDisplayName({ displayName: "  Linh  ", name: "x" })).toBe("Linh");
    expect(pickDisplayName({ displayName: "   ", name: "Nguyen" })).toBe("Nguyen");
  });

  it("returns null when there is nothing usable, so the header says just 'Welcome back'", () => {
    expect(pickDisplayName({ displayName: null, name: "" })).toBeNull();
    expect(pickDisplayName({ displayName: " ", name: " " })).toBeNull();
    expect(pickDisplayName(null)).toBeNull();
  });
});

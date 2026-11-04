import { describe, expect, it } from "vitest";
import { sanitizeRedirect, DEFAULT_REDIRECT } from "./redirect";

describe("sanitizeRedirect", () => {
  it("returns the default for missing/empty input", () => {
    expect(sanitizeRedirect(undefined)).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect(null)).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("")).toBe(DEFAULT_REDIRECT);
  });

  it("passes through valid same-origin relative paths", () => {
    expect(sanitizeRedirect("/profile/overview")).toBe("/profile/overview");
    expect(sanitizeRedirect("/profile/trips/123?tab=1")).toBe("/profile/trips/123?tab=1");
    expect(sanitizeRedirect("/")).toBe("/");
  });

  it("rejects protocol-relative URLs", () => {
    expect(sanitizeRedirect("//evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("//evil.com/path")).toBe(DEFAULT_REDIRECT);
  });

  it("rejects absolute URLs", () => {
    expect(sanitizeRedirect("https://evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("http://evil.com/profile")).toBe(DEFAULT_REDIRECT);
  });

  it("rejects backslash tricks", () => {
    expect(sanitizeRedirect("/\\evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("\\evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("\\/evil.com")).toBe(DEFAULT_REDIRECT);
  });

  it("stays same-origin even for a percent-encoded double-slash segment", () => {
    // Browsers never decode %2F when resolving a path for origin purposes,
    // so this can only ever resolve to a literal (harmless) same-origin
    // path — never an actual navigation to evil.com.
    const result = sanitizeRedirect("/%2F%2Fevil.com");
    expect(result.startsWith("/")).toBe(true);
    expect(new URL(result, "http://localhost:3000").origin).toBe("http://localhost:3000");
  });

  it("rejects control characters anywhere in the value", () => {
    expect(sanitizeRedirect("/\t/evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("/\n/evil.com")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("/profile\r\n/evil.com")).toBe(DEFAULT_REDIRECT);
  });

  it("rejects javascript: values", () => {
    expect(sanitizeRedirect("javascript:alert(1)")).toBe(DEFAULT_REDIRECT);
    expect(sanitizeRedirect("/javascript:alert(1)")).toBe(DEFAULT_REDIRECT);
  });
});

import { describe, expect, it } from "vitest";
import { friendlyAuthErrorMessage, IDENTITY_ALREADY_EXISTS } from "./errors";

describe("friendlyAuthErrorMessage", () => {
  it("maps identity_already_exists to its specific recovery message", () => {
    expect(friendlyAuthErrorMessage(IDENTITY_ALREADY_EXISTS)).toMatch(/already linked/i);
  });

  it("maps other known codes to their fixed message", () => {
    expect(friendlyAuthErrorMessage("access_denied")).toBe("Sign-in was cancelled.");
  });

  it("falls back to a generic message for unknown codes", () => {
    expect(friendlyAuthErrorMessage("some_future_gotrue_code")).toBe(
      "Sign-in failed. Please try again.",
    );
  });

  it("falls back to the generic message for null/undefined", () => {
    expect(friendlyAuthErrorMessage(null)).toBe("Sign-in failed. Please try again.");
    expect(friendlyAuthErrorMessage(undefined)).toBe("Sign-in failed. Please try again.");
  });

  it("never echoes arbitrary input back as a message (no error_description passthrough)", () => {
    const attackerString = "<script>alert(1)</script>";
    expect(friendlyAuthErrorMessage(attackerString)).not.toContain("<script>");
  });
});

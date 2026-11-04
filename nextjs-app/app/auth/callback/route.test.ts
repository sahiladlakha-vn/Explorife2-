import { describe, expect, it, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));

import { createClient } from "@/lib/supabase/server";
import { GET } from "./route";

const SITE_URL = "http://localhost:3000";

function callbackRequest(query: Record<string, string>): NextRequest {
  const params = new URLSearchParams(query);
  return new NextRequest(`${SITE_URL}/auth/callback?${params.toString()}`);
}

function mockExchange(result: { error: { message: string } | null }) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      exchangeCodeForSession: vi.fn().mockResolvedValue(result),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub
  } as any);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("GET /auth/callback", () => {
  it("forwards error_code (e.g. identity_already_exists) to /auth, never calling Supabase", async () => {
    const request = callbackRequest({
      error: "server_error",
      error_code: "identity_already_exists",
      error_description: "Should never be forwarded",
      provider: "google",
      redirect: "/profile/overview",
    });

    const response = await GET(request);

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      `${SITE_URL}/auth?redirect=%2Fprofile%2Foverview&error=identity_already_exists&provider=google`,
    );
    expect(createClient).not.toHaveBeenCalled();
  });

  it("falls back to the bare `error` param when there's no error_code", async () => {
    const request = callbackRequest({ error: "access_denied", redirect: "/profile/overview" });

    const response = await GET(request);

    expect(response.headers.get("location")).toBe(
      `${SITE_URL}/auth?redirect=%2Fprofile%2Foverview&error=access_denied`,
    );
  });

  it("redirects to a server_error when there's neither a code nor an error", async () => {
    const request = callbackRequest({ redirect: "/profile/overview" });

    const response = await GET(request);

    expect(response.headers.get("location")).toBe(
      `${SITE_URL}/auth?redirect=%2Fprofile%2Foverview&error=server_error`,
    );
  });

  it("exchanges a valid code and redirects to the sanitized destination", async () => {
    mockExchange({ error: null });
    const request = callbackRequest({ code: "abc123", redirect: "/profile/saved" });

    const response = await GET(request);

    expect(response.headers.get("location")).toBe(`${SITE_URL}/profile/saved`);
  });

  it("redirects to a server_error when exchangeCodeForSession itself fails", async () => {
    mockExchange({ error: { message: "invalid grant" } });
    const request = callbackRequest({ code: "expired-code", redirect: "/profile/overview" });

    const response = await GET(request);

    expect(response.headers.get("location")).toBe(
      `${SITE_URL}/auth?redirect=%2Fprofile%2Foverview&error=server_error`,
    );
  });

  it("sanitizes a malicious redirect before embedding it in any response", async () => {
    const request = callbackRequest({ error: "access_denied", redirect: "//evil.com" });

    const response = await GET(request);

    expect(response.headers.get("location")).toBe(
      `${SITE_URL}/auth?redirect=%2Fprofile%2Foverview&error=access_denied`,
    );
  });
});

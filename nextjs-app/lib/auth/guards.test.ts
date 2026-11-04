import { describe, expect, it, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));

class RedirectSignal extends Error {
  constructor(public url: string) {
    super(`NEXT_REDIRECT:${url}`);
  }
}

vi.mock("next/navigation", () => ({
  redirect: vi.fn((url: string) => {
    throw new RedirectSignal(url);
  }),
}));

import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { requireRealUserOrRedirect } from "./guards";

function mockSessionUser(user: Pick<User, "id" | "is_anonymous"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub
  } as any);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("requireRealUserOrRedirect", () => {
  it("returns the user when a real (non-anonymous) session exists", async () => {
    mockSessionUser({ id: "user-1", is_anonymous: false });
    await expect(requireRealUserOrRedirect("/profile/settings")).resolves.toEqual({
      id: "user-1",
      is_anonymous: false,
    });
    expect(redirect).not.toHaveBeenCalled();
  });

  it("redirects to /auth?redirect=<path> when there's no session", async () => {
    mockSessionUser(null);
    await expect(requireRealUserOrRedirect("/profile/settings")).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith("/auth?redirect=%2Fprofile%2Fsettings");
  });

  it("redirects to /auth?redirect=<path> for an anonymous/guest session", async () => {
    mockSessionUser({ id: "guest-1", is_anonymous: true });
    await expect(requireRealUserOrRedirect("/profile/settings")).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith("/auth?redirect=%2Fprofile%2Fsettings");
  });

  it("sanitizes a malicious currentPath before building the redirect URL", async () => {
    mockSessionUser(null);
    await expect(requireRealUserOrRedirect("//evil.com")).rejects.toThrow(RedirectSignal);
    // sanitizeRedirect falls back to the default for a protocol-relative path.
    expect(redirect).toHaveBeenCalledWith("/auth?redirect=%2Fprofile%2Foverview");
  });
});

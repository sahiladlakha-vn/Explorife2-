import { describe, expect, it, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => ({
  prisma: {
    profile: {
      findUnique: vi.fn(),
    },
  },
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
import { prisma } from "@/lib/db";
import { redirect } from "next/navigation";
import type { Role } from "./permissions";
import { requireRealUserOrRedirect, requireAdminOrRedirect } from "./guards";

function mockSessionUser(user: Pick<User, "id" | "is_anonymous"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub
  } as any);
}

function mockProfileRole(role: Role | null) {
  vi.mocked(prisma.profile.findUnique).mockResolvedValue(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected/read by getUserRole()
    (role === null ? null : { role }) as any,
  );
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

describe("requireAdminOrRedirect", () => {
  it("redirects to /auth?redirect=<path> when there's no session", async () => {
    mockSessionUser(null);
    await expect(requireAdminOrRedirect("/admin/dashboard")).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith("/auth?redirect=%2Fadmin%2Fdashboard");
  });

  it("redirects to /auth?redirect=<path> for an anonymous/guest session", async () => {
    mockSessionUser({ id: "guest-1", is_anonymous: true });
    await expect(requireAdminOrRedirect("/admin/dashboard")).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith("/auth?redirect=%2Fadmin%2Fdashboard");
  });

  it("redirects a signed-in non-admin to /profile", async () => {
    mockSessionUser({ id: "user-1", is_anonymous: false });
    mockProfileRole("traveler");
    await expect(requireAdminOrRedirect("/admin/dashboard")).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith("/profile");
  });

  it.each(["super_admin", "finance_admin", "regional_admin", "content_moderator"] as const)(
    "resolves for a %s without redirecting",
    async (role) => {
      mockSessionUser({ id: "user-1", is_anonymous: false });
      mockProfileRole(role);
      await expect(requireAdminOrRedirect("/admin/dashboard")).resolves.toEqual({
        user: { id: "user-1", is_anonymous: false },
        role,
      });
      expect(redirect).not.toHaveBeenCalled();
    },
  );
});

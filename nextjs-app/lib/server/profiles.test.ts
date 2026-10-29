import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/auth/permissions.test.ts — see that file's
// top-of-file comment for why `createClient()`/`prisma` are mocked rather
// than hit for real.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => ({
  prisma: {
    profile: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
  },
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError, ForbiddenError, type Role } from "@/lib/auth/permissions";
import { updateProfile, updateUserRole } from "./profiles";

function mockSessionUser(user: Pick<User, "id"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub, only `auth.getUser()` is exercised
  } as any);
}

function mockActorRole(role: Role | null) {
  vi.mocked(prisma.profile.findUnique).mockResolvedValue(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected/read by getUserRole()
    (role === null ? null : { role }) as any,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("updateProfile", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(updateProfile("user-1", { bio: "hi" })).rejects.toBeInstanceOf(AuthError);
    expect(prisma.profile.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError when a non-owner, non-admin edits someone else's profile", async () => {
    mockSessionUser({ id: "user-2" });
    mockActorRole("traveler");
    await expect(updateProfile("user-1", { bio: "hi" })).rejects.toBeInstanceOf(ForbiddenError);
    expect(prisma.profile.update).not.toHaveBeenCalled();
  });

  it("lets the owner edit their own non-locked fields (no role check needed)", async () => {
    mockSessionUser({ id: "user-1" });
    // Deliberately no mockActorRole() call: a plain self-edit with no `role`
    // in the patch must never need to look up the actor's role at all.
    await updateProfile("user-1", { bio: "new bio", city: "Hanoi" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "new bio", city: "Hanoi" },
    });
    expect(prisma.profile.findUnique).not.toHaveBeenCalled();
  });

  it("lets an admin-tier role edit someone else's non-locked fields", async () => {
    mockSessionUser({ id: "admin-1" });
    mockActorRole("regional_admin");
    await updateProfile("user-1", { bio: "moderated" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "moderated" },
    });
  });

  it("silently strips `role` (keeps the rest of the patch) when the owner isn't a super_admin — mirrors lock_profile_role_field()'s revert-only-role behavior", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    await updateProfile("user-1", { bio: "new bio", role: "super_admin" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "new bio" },
    });
  });

  it("keeps `role` in the patch when the caller is a super_admin", async () => {
    mockSessionUser({ id: "admin-1" });
    mockActorRole("super_admin");
    await updateProfile("user-1", { bio: "new bio", role: "guide" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "new bio", role: "guide" },
    });
  });
});

describe("updateUserRole", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(updateUserRole("user-1", "super_admin")).rejects.toBeInstanceOf(AuthError);
    expect(prisma.profile.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError for a signed-in non-super_admin — no partial write", async () => {
    mockSessionUser({ id: "user-2" });
    mockActorRole("regional_admin");
    await expect(updateUserRole("user-1", "super_admin")).rejects.toBeInstanceOf(ForbiddenError);
    expect(prisma.profile.update).not.toHaveBeenCalled();
  });

  it("resolves and writes the role for a super_admin", async () => {
    mockSessionUser({ id: "admin-1" });
    mockActorRole("super_admin");
    await updateUserRole("user-1", "content_moderator");
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { role: "content_moderator" },
    });
  });
});

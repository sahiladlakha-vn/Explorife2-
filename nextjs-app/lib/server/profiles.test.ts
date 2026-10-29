import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/auth/permissions.test.ts — see that file's
// top-of-file comment for why `createClient()`/`prisma` are mocked rather
// than hit for real.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => {
  // Defined and returned entirely inside the factory (rather than referencing
  // an outer-scope variable) to dodge vi.mock's hoisting — $transaction needs
  // to invoke its callback with the *same* mocked client so `tx.profile.*`
  // calls inside updateUserRole's transaction hit the exact mocks the tests
  // configure via `prisma.profile.*`.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, shape mirrors the real PrismaClient subset this module uses
  const prismaMock: any = {
    profile: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
    adminActionLog: {
      create: vi.fn(),
    },
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double
  prismaMock.$transaction = vi.fn((callback: (tx: any) => unknown) => callback(prismaMock));
  return { prisma: prismaMock };
});

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

  it("lets a super_admin edit someone else's non-locked fields", async () => {
    mockSessionUser({ id: "admin-1" });
    mockActorRole("super_admin");
    await updateProfile("user-1", { bio: "moderated" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "moderated" },
    });
  });

  // RLS parity: the live `profiles_update_admin` policy only grants
  // `is_super_admin()`, not the broader admin-tier set — regional_admin/
  // content_moderator/finance_admin have no RLS grant to edit someone
  // *else's* profile row at all, only their own.
  it.each(["regional_admin", "content_moderator", "finance_admin"] as const)(
    "throws ForbiddenError when a %s (non-super_admin) edits someone else's profile",
    async (role) => {
      mockSessionUser({ id: "admin-1" });
      mockActorRole(role);
      await expect(updateProfile("user-1", { bio: "moderated" })).rejects.toBeInstanceOf(
        ForbiddenError,
      );
      expect(prisma.profile.update).not.toHaveBeenCalled();
    },
  );

  it("silently strips `role` (keeps the rest of the patch) when the owner isn't a super_admin — mirrors lock_profile_role_field()'s revert-only-role behavior", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    await updateProfile("user-1", { bio: "new bio", role: "super_admin" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "new bio" },
    });
    expect(warnSpy).toHaveBeenCalledTimes(1);
    const [message] = warnSpy.mock.calls[0];
    expect(message).toContain("table=profiles");
    expect(message).toContain("recordId=user-1");
    expect(message).toContain("userId=user-1");
    expect(message).toContain("fields=role");
    warnSpy.mockRestore();
  });

  it("keeps `role` in the patch when the caller is a super_admin, and does not warn", async () => {
    mockSessionUser({ id: "admin-1" });
    mockActorRole("super_admin");
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    await updateProfile("user-1", { bio: "new bio", role: "guide" });
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { bio: "new bio", role: "guide" },
    });
    expect(warnSpy).not.toHaveBeenCalled();
    warnSpy.mockRestore();
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

  it("resolves and writes the role for a super_admin, and logs the change in admin_action_log", async () => {
    mockSessionUser({ id: "admin-1" });
    // First findUnique call is the actor's own role check (assertCanChangeProfileRole);
    // second is the target's old role, read inside the transaction.
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "traveler" } as any);

    await updateUserRole("user-1", "content_moderator");

    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "user-1" },
      data: { role: "content_moderator" },
    });
    expect(prisma.adminActionLog.create).toHaveBeenCalledWith({
      data: {
        actorId: "admin-1",
        actionType: "assign_role",
        targetProfileId: "user-1",
        oldRole: "traveler",
        newRole: "content_moderator",
        details: { old_role: "traveler", new_role: "content_moderator" },
      },
    });
  });

  it("records a null old_role in admin_action_log when the target profile can't be found", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(null);

    await updateUserRole("user-missing", "content_moderator");

    expect(prisma.adminActionLog.create).toHaveBeenCalledWith({
      data: {
        actorId: "admin-1",
        actionType: "assign_role",
        targetProfileId: "user-missing",
        oldRole: null,
        newRole: "content_moderator",
        details: { old_role: null, new_role: "content_moderator" },
      },
    });
  });
});

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
      count: vi.fn(),
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
import { Prisma } from "@/lib/generated/prisma/client";
import { AuthError, ForbiddenError, type Role } from "@/lib/auth/permissions";
import { ConcurrentRoleChangeError, updateProfile, updateUserRole } from "./profiles";

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

/**
 * Shapes `updateUserRole`'s target lookup: `tx.profile.findUnique({ ...,
 * include: { user: { select: { isAnonymous: true } } } })`. `isAnonymous`
 * defaults to `false` since most tests aren't exercising that guard.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, shape mirrors the joined Profile+User.isAnonymous read
function targetProfile(role: Role, isAnonymous = false): any {
  return { role, user: { isAnonymous } };
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
    // second is the target's profile + isAnonymous, read inside the transaction.
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("traveler"));

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

  // Guard 2 (profile not found): the live RPC raises `profile not found: %`
  // for a missing target — no partial write.
  it("throws when the target profile doesn't exist — no partial write", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // Actor's own role check (assertCanChangeProfileRole).
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      // Target lookup inside the transaction.
      .mockResolvedValueOnce(null);

    await expect(updateUserRole("user-missing", "content_moderator")).rejects.toThrow(
      "Profile user-missing not found.",
    );
    expect(prisma.profile.update).not.toHaveBeenCalled();
    expect(prisma.adminActionLog.create).not.toHaveBeenCalled();
  });

  // Guard 3 (anonymous guest target): read via the same Prisma join as the
  // not-found check (`User.isAnonymous`, see prisma/schema.prisma), inside
  // the Serializable transaction — no separate pre-transaction round-trip.
  it("throws ForbiddenError when the target is an anonymous guest session", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("traveler", true));

    await expect(updateUserRole("guest-1", "content_moderator")).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.profile.update).not.toHaveBeenCalled();
    expect(prisma.adminActionLog.create).not.toHaveBeenCalled();
  });

  // Guard 4 (same-role no-op): `if v_old_role = p_new_role then return;` —
  // no update, no admin_action_log row.
  it("is a no-op (no update, no audit log row) when the new role matches the current role", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("content_moderator"));

    const result = await updateUserRole("user-1", "content_moderator");

    expect(result).toEqual(targetProfile("content_moderator"));
    expect(prisma.profile.update).not.toHaveBeenCalled();
    expect(prisma.adminActionLog.create).not.toHaveBeenCalled();
  });

  // Guard 5 (last-super_admin self-demotion), blocked case: self-target +
  // non-super_admin new role + only one super_admin left.
  it("throws ForbiddenError when a super_admin tries to self-demote and is the last super_admin", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("super_admin"));
    vi.mocked(prisma.profile.count).mockResolvedValue(1);

    await expect(updateUserRole("admin-1", "content_moderator")).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.profile.count).toHaveBeenCalledWith({ where: { role: "super_admin" } });
    expect(prisma.profile.update).not.toHaveBeenCalled();
    expect(prisma.adminActionLog.create).not.toHaveBeenCalled();
  });

  // Guard 5, allowed case: self-demotion is fine once a second super_admin exists.
  it("allows a super_admin to self-demote when another super_admin still exists", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("super_admin"));
    vi.mocked(prisma.profile.count).mockResolvedValue(2);

    await updateUserRole("admin-1", "content_moderator");

    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "admin-1" },
      data: { role: "content_moderator" },
    });
    expect(prisma.adminActionLog.create).toHaveBeenCalled();
  });

  // Guard 5's exact condition is self-target-only — demoting a DIFFERENT
  // super_admin never runs the count check at all, even if they're the only
  // other one (matches `p_target_id = auth.uid() AND ...` in the live RPC).
  it("allows demoting a different super_admin without ever running the last-super-admin count check", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("super_admin"));

    await updateUserRole("admin-2", "content_moderator");

    expect(prisma.profile.count).not.toHaveBeenCalled();
    expect(prisma.profile.update).toHaveBeenCalledWith({
      where: { id: "admin-2" },
      data: { role: "content_moderator" },
    });
  });

  // Concurrency fix (beyond the original RPC): the whole guard+update chain
  // must run under Serializable isolation so two concurrent last-super-admin
  // self-demotions can't both commit (write-skew).
  it("runs the guard+update chain in a Serializable-isolation transaction", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any)
      .mockResolvedValueOnce(targetProfile("traveler"));

    await updateUserRole("user-1", "content_moderator");

    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
    });
  });

  // Concurrency fix's error surface: the "loser" of a write-skew race gets
  // Prisma's raw P2034 from $transaction — mapped here to a clear,
  // actionable message instead of leaking a Prisma error code to an admin.
  it("maps a P2034 write-conflict error to ConcurrentRoleChangeError with a clear retry message", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any);
    const conflictError = new Prisma.PrismaClientKnownRequestError(
      "Transaction failed due to a write conflict or a deadlock. Please retry your transaction",
      { code: "P2034", clientVersion: "test" },
    );
    vi.mocked(prisma.$transaction).mockRejectedValueOnce(conflictError);

    let thrown: unknown;
    try {
      await updateUserRole("user-1", "content_moderator");
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ConcurrentRoleChangeError);
    expect((thrown as Error).message).toBe("Roles were changed at the same time — please try again.");
  });

  it("does not remap other $transaction errors (e.g. a different Prisma error code)", async () => {
    mockSessionUser({ id: "admin-1" });
    vi.mocked(prisma.profile.findUnique)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `role` is selected
      .mockResolvedValueOnce({ role: "super_admin" } as any);
    const otherError = new Prisma.PrismaClientKnownRequestError("Some other failure", {
      code: "P2002",
      clientVersion: "test",
    });
    vi.mocked(prisma.$transaction).mockRejectedValueOnce(otherError);

    await expect(updateUserRole("user-1", "content_moderator")).rejects.toBe(otherError);
  });
});

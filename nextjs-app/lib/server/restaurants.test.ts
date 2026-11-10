import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/auth/permissions.test.ts.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, shape mirrors the real PrismaClient subset this module uses
  const prismaMock: any = {
    profile: {
      findUnique: vi.fn(),
    },
    restaurant: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
    // `runAsUser` (lib/server/db-as-user.ts) issues this as the first
    // statement inside the transaction, before any `tx.restaurant.*` calls.
    $executeRaw: vi.fn(),
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double
  prismaMock.$transaction = vi.fn((callback: (tx: any) => unknown) => callback(prismaMock));
  return { prisma: prismaMock };
});

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError, ForbiddenError, type Role } from "@/lib/auth/permissions";
import {
  RestaurantVerificationRevertedError,
  updateRestaurant,
  setRestaurantVerification,
} from "./restaurants";

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

function mockRestaurantOwner(ownerId: string | null) {
  vi.mocked(prisma.restaurant.findUnique).mockResolvedValue(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `ownerId` is selected
    (ownerId === null ? null : { ownerId }) as any,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("updateRestaurant", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(updateRestaurant("rest-1", { name: "New name" })).rejects.toBeInstanceOf(
      AuthError,
    );
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("throws when the restaurant doesn't exist", async () => {
    mockSessionUser({ id: "user-1" });
    mockRestaurantOwner(null);
    await expect(updateRestaurant("rest-missing", { name: "New name" })).rejects.toThrow(
      "not found",
    );
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError when a non-owner, non-admin edits someone else's listing", async () => {
    mockSessionUser({ id: "user-2" });
    mockRestaurantOwner("user-1");
    mockActorRole("traveler");
    await expect(updateRestaurant("rest-1", { name: "New name" })).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  // Same behavior-difference case as attractions: the live trigger only ever
  // reverts verification_status/verified_by/verified_at and never blocks the
  // rest of the UPDATE.
  it("lets the owner edit their own non-locked fields", async () => {
    mockSessionUser({ id: "user-1" });
    mockRestaurantOwner("user-1");
    await updateRestaurant("rest-1", { name: "New name", phone: "+84123456789" });
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: { name: "New name", phone: "+84123456789" },
    });
    expect(prisma.profile.findUnique).not.toHaveBeenCalled();
  });

  it("lets an admin-tier role edit someone else's non-locked fields", async () => {
    mockSessionUser({ id: "admin-1" });
    mockRestaurantOwner("user-1");
    mockActorRole("regional_admin");
    await updateRestaurant("rest-1", { name: "Moderated name" });
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: { name: "Moderated name" },
    });
  });

  it("silently strips all three verification fields (keeps the rest) when the owner isn't a moderator — mirrors lock_restaurant_verification_fields()'s revert-as-a-group behavior", async () => {
    mockSessionUser({ id: "user-1" });
    mockRestaurantOwner("user-1");
    mockActorRole("traveler");
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    await updateRestaurant("rest-1", {
      name: "New name",
      verificationStatus: "verified",
      verifiedBy: "user-1",
      verifiedAt: new Date("2026-01-01"),
    });
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: { name: "New name" },
    });
    expect(warnSpy).toHaveBeenCalledTimes(1);
    const [message] = warnSpy.mock.calls[0];
    expect(message).toContain("table=restaurants");
    expect(message).toContain("recordId=rest-1");
    expect(message).toContain("userId=user-1");
    expect(message).toContain("fields=verificationStatus,verifiedBy,verifiedAt");
    warnSpy.mockRestore();
  });

  it("keeps the verification fields when the caller is a moderator, and does not warn", async () => {
    mockSessionUser({ id: "mod-1" });
    mockRestaurantOwner("user-1");
    mockActorRole("content_moderator");
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const verifiedAt = new Date("2026-01-01");
    await updateRestaurant("rest-1", {
      verificationStatus: "verified",
      verifiedBy: "mod-1",
      verifiedAt,
    });
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: { verificationStatus: "verified", verifiedBy: "mod-1", verifiedAt },
    });
    expect(warnSpy).not.toHaveBeenCalled();
    warnSpy.mockRestore();
  });
});

describe("setRestaurantVerification", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(setRestaurantVerification("rest-1", "verified")).rejects.toBeInstanceOf(
      AuthError,
    );
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError for a signed-in traveler — no partial write", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    await expect(setRestaurantVerification("rest-1", "verified")).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("resolves and writes verification for a content_moderator, computing verifiedBy/verifiedAt server-side", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    // Post-write re-read inside the same `runAsUser` transaction — confirms
    // `lock_restaurant_verification_fields` didn't revert the write.
    vi.mocked(prisma.restaurant.findUnique).mockResolvedValue({
      verificationStatus: "verified",
      verifiedBy: "mod-1",
      verifiedAt: new Date("2026-01-01T00:00:00.000Z"),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, only the verification columns are read back
    } as any);

    await setRestaurantVerification("rest-1", "verified");

    expect(prisma.$executeRaw).toHaveBeenCalled();
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: {
        verificationStatus: "verified",
        verifiedBy: "mod-1",
        verifiedAt: new Date("2026-01-01T00:00:00.000Z"),
      },
    });
    vi.useRealTimers();
  });

  // `runAsUser` guard: if the trigger reverts the write anyway (e.g. the
  // transaction-local claim didn't take effect), the re-read must catch it
  // and the function must throw rather than report success.
  it("throws RestaurantVerificationRevertedError when the re-read shows the trigger reverted the write", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    vi.mocked(prisma.restaurant.findUnique).mockResolvedValue({
      verificationStatus: "pending",
      verifiedBy: null,
      verifiedAt: null,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double
    } as any);

    await expect(setRestaurantVerification("rest-1", "verified")).rejects.toBeInstanceOf(
      RestaurantVerificationRevertedError,
    );
  });

  // The whole point of computing these server-side: a caller can't pass a
  // different moderator's id or a backdated timestamp through — there's no
  // parameter for either anymore, but this guards against a future signature
  // regression that re-adds one without updating this test.
  it("ignores any attempt to pass verifiedBy/verifiedAt — the function signature has no such parameters", () => {
    expect(setRestaurantVerification.length).toBe(2);
  });
});

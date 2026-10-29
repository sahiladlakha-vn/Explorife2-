import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/auth/permissions.test.ts.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => ({
  prisma: {
    profile: {
      findUnique: vi.fn(),
    },
    restaurant: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
  },
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError, ForbiddenError, type Role } from "@/lib/auth/permissions";
import { updateRestaurant, setRestaurantVerification } from "./restaurants";

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
  });

  it("keeps the verification fields when the caller is a moderator", async () => {
    mockSessionUser({ id: "mod-1" });
    mockRestaurantOwner("user-1");
    mockActorRole("content_moderator");
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
  });
});

describe("setRestaurantVerification", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(
      setRestaurantVerification("rest-1", "verified", "mod-1", new Date()),
    ).rejects.toBeInstanceOf(AuthError);
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError for a signed-in traveler — no partial write", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    await expect(
      setRestaurantVerification("rest-1", "verified", "user-1", new Date()),
    ).rejects.toBeInstanceOf(ForbiddenError);
    expect(prisma.restaurant.update).not.toHaveBeenCalled();
  });

  it("resolves and writes verification for a content_moderator", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    const verifiedAt = new Date("2026-01-01");
    await setRestaurantVerification("rest-1", "verified", "mod-1", verifiedAt);
    expect(prisma.restaurant.update).toHaveBeenCalledWith({
      where: { id: "rest-1" },
      data: { verificationStatus: "verified", verifiedBy: "mod-1", verifiedAt },
    });
  });
});

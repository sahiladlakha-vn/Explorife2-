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
    attraction: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
  },
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError, ForbiddenError, type Role } from "@/lib/auth/permissions";
import { updateAttraction, setAttractionVerification } from "./attractions";

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

function mockAttractionOwner(ownerId: string | null) {
  vi.mocked(prisma.attraction.findUnique).mockResolvedValue(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `ownerId` is selected
    (ownerId === null ? null : { ownerId }) as any,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("updateAttraction", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(updateAttraction("attr-1", { name: "New name" })).rejects.toBeInstanceOf(
      AuthError,
    );
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("throws when the attraction doesn't exist", async () => {
    mockSessionUser({ id: "user-1" });
    mockAttractionOwner(null);
    await expect(updateAttraction("attr-missing", { name: "New name" })).rejects.toThrow(
      "not found",
    );
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError when a non-owner, non-admin edits someone else's listing", async () => {
    mockSessionUser({ id: "user-2" });
    mockAttractionOwner("user-1");
    mockActorRole("traveler");
    await expect(updateAttraction("attr-1", { name: "New name" })).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  // This is the specific behavior difference flagged for review: the live
  // trigger only ever reverts verification_status/verified_by/verified_at —
  // it never blocks the rest of the UPDATE, so an owner editing their own
  // listing's ordinary fields must keep working even though they can never
  // set verification fields themselves.
  it("lets the owner edit their own non-locked fields", async () => {
    mockSessionUser({ id: "user-1" });
    mockAttractionOwner("user-1");
    await updateAttraction("attr-1", { name: "New name", description: "Updated" });
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
      data: { name: "New name", description: "Updated" },
    });
    // No verification fields touched -> no role lookup needed at all.
    expect(prisma.profile.findUnique).not.toHaveBeenCalled();
  });

  it("lets an admin-tier role edit someone else's non-locked fields", async () => {
    mockSessionUser({ id: "admin-1" });
    mockAttractionOwner("user-1");
    mockActorRole("regional_admin");
    await updateAttraction("attr-1", { name: "Moderated name" });
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
      data: { name: "Moderated name" },
    });
  });

  it("silently strips all three verification fields (keeps the rest) when the owner isn't a moderator — mirrors lock_attraction_verification_fields()'s revert-as-a-group behavior", async () => {
    mockSessionUser({ id: "user-1" });
    mockAttractionOwner("user-1");
    mockActorRole("traveler");
    await updateAttraction("attr-1", {
      name: "New name",
      verificationStatus: "verified",
      verifiedBy: "user-1",
      verifiedAt: new Date("2026-01-01"),
    });
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
      data: { name: "New name" },
    });
  });

  it("keeps the verification fields when the caller is a moderator", async () => {
    mockSessionUser({ id: "mod-1" });
    mockAttractionOwner("user-1");
    mockActorRole("content_moderator");
    const verifiedAt = new Date("2026-01-01");
    await updateAttraction("attr-1", {
      verificationStatus: "verified",
      verifiedBy: "mod-1",
      verifiedAt,
    });
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
      data: { verificationStatus: "verified", verifiedBy: "mod-1", verifiedAt },
    });
  });
});

describe("setAttractionVerification", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(
      setAttractionVerification("attr-1", "verified", "mod-1", new Date()),
    ).rejects.toBeInstanceOf(AuthError);
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError for a signed-in traveler — no partial write", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    await expect(
      setAttractionVerification("attr-1", "verified", "user-1", new Date()),
    ).rejects.toBeInstanceOf(ForbiddenError);
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("resolves and writes verification for a content_moderator", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    const verifiedAt = new Date("2026-01-01");
    await setAttractionVerification("attr-1", "verified", "mod-1", verifiedAt);
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
      data: { verificationStatus: "verified", verifiedBy: "mod-1", verifiedAt },
    });
  });
});

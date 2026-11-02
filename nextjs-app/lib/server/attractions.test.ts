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
    attraction: {
      findUnique: vi.fn(),
      update: vi.fn(),
    },
    // `runAsUser` (lib/server/db-as-user.ts) issues this as the first
    // statement inside the transaction, before any `tx.attraction.*` calls.
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
  AttractionVerificationRevertedError,
  updateAttraction,
  setAttractionVerification,
} from "./attractions";

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
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
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
    expect(warnSpy).toHaveBeenCalledTimes(1);
    const [message] = warnSpy.mock.calls[0];
    expect(message).toContain("table=attractions");
    expect(message).toContain("recordId=attr-1");
    expect(message).toContain("userId=user-1");
    expect(message).toContain("fields=verificationStatus,verifiedBy,verifiedAt");
    warnSpy.mockRestore();
  });

  it("keeps the verification fields when the caller is a moderator, and does not warn", async () => {
    mockSessionUser({ id: "mod-1" });
    mockAttractionOwner("user-1");
    mockActorRole("content_moderator");
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
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
    expect(warnSpy).not.toHaveBeenCalled();
    warnSpy.mockRestore();
  });
});

describe("setAttractionVerification", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(setAttractionVerification("attr-1", "verified")).rejects.toBeInstanceOf(
      AuthError,
    );
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("throws ForbiddenError for a signed-in traveler — no partial write", async () => {
    mockSessionUser({ id: "user-1" });
    mockActorRole("traveler");
    await expect(setAttractionVerification("attr-1", "verified")).rejects.toBeInstanceOf(
      ForbiddenError,
    );
    expect(prisma.attraction.update).not.toHaveBeenCalled();
  });

  it("resolves and writes verification for a content_moderator, computing verifiedBy/verifiedAt server-side", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    // Post-write re-read inside the same `runAsUser` transaction — confirms
    // `lock_attraction_verification_fields` didn't revert the write.
    vi.mocked(prisma.attraction.findUnique).mockResolvedValue({
      verificationStatus: "verified",
      verifiedBy: "mod-1",
      verifiedAt: new Date("2026-01-01T00:00:00.000Z"),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, only the verification columns are read back
    } as any);

    await setAttractionVerification("attr-1", "verified");

    expect(prisma.$executeRaw).toHaveBeenCalled();
    expect(prisma.attraction.update).toHaveBeenCalledWith({
      where: { id: "attr-1" },
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
  it("throws AttractionVerificationRevertedError when the re-read shows the trigger reverted the write", async () => {
    mockSessionUser({ id: "mod-1" });
    mockActorRole("content_moderator");
    // Re-read shows the old (unverified) values — the trigger fired as if
    // the caller weren't a moderator.
    vi.mocked(prisma.attraction.findUnique).mockResolvedValue({
      verificationStatus: "pending",
      verifiedBy: null,
      verifiedAt: null,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double
    } as any);

    await expect(setAttractionVerification("attr-1", "verified")).rejects.toBeInstanceOf(
      AttractionVerificationRevertedError,
    );
  });

  // The whole point of computing these server-side: a caller can't pass a
  // different moderator's id or a backdated timestamp through — there's no
  // parameter for either anymore, but this guards against a future signature
  // regression that re-adds one without updating this test.
  it("ignores any attempt to pass verifiedBy/verifiedAt — the function signature has no such parameters", () => {
    expect(setAttractionVerification.length).toBe(2);
  });
});

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Mocked instead of hit for real: `createClient()` normally opens a
// `@supabase/ssr` session scoped to the current request's cookies (see
// lib/supabase/server.ts), and `prisma` (lib/db.ts) normally hits the live
// Postgres instance. Neither belongs in a unit test — these mocks let us
// drive `getCurrentUser()`/`getUserRole()` deterministically.
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

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import {
  AuthError,
  ForbiddenError,
  getUserRole,
  canChangeProfileRole,
  canSetListingVerification,
  assertCanChangeProfileRole,
  assertCanVerifyAttraction,
  assertCanVerifyRestaurant,
  PROFILE_ROLE_CHANGE_ROLES,
  VERIFICATION_MODERATOR_ROLES,
  type Role,
} from "./permissions";

const ALL_ROLES: readonly Role[] = [
  "traveler",
  "guide",
  "business_owner",
  "content_moderator",
  "regional_admin",
  "super_admin",
  "finance_admin",
];

function mockSessionUser(user: Pick<User, "id"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub, only `auth.getUser()` is exercised
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

// --- Pure predicates -----------------------------------------------------
//
// These mirror the live trigger SQL directly (see prisma/db-notes.sql §2) and
// need no mocking at all — exercising every Role plus `null` (unauthenticated/
// no-profile) pins down the exact same role lists the triggers use.

describe("canChangeProfileRole", () => {
  it("mirrors lock_profile_role_field(): only super_admin", () => {
    for (const role of ALL_ROLES) {
      expect(canChangeProfileRole(role)).toBe(role === "super_admin");
    }
  });

  it("is false for null (no session / no profile)", () => {
    expect(canChangeProfileRole(null)).toBe(false);
  });

  it("agrees with the exported PROFILE_ROLE_CHANGE_ROLES list", () => {
    for (const role of ALL_ROLES) {
      expect(canChangeProfileRole(role)).toBe(PROFILE_ROLE_CHANGE_ROLES.includes(role));
    }
  });
});

describe("canSetListingVerification", () => {
  it("mirrors lock_{attraction,restaurant}_verification_fields(): content_moderator/regional_admin/super_admin", () => {
    const expectedAllowed: readonly Role[] = ["content_moderator", "regional_admin", "super_admin"];
    for (const role of ALL_ROLES) {
      expect(canSetListingVerification(role)).toBe(expectedAllowed.includes(role));
    }
  });

  it("is false for null (no session / no profile)", () => {
    expect(canSetListingVerification(null)).toBe(false);
  });

  it("agrees with the exported VERIFICATION_MODERATOR_ROLES list", () => {
    for (const role of ALL_ROLES) {
      expect(canSetListingVerification(role)).toBe(VERIFICATION_MODERATOR_ROLES.includes(role));
    }
  });
});

// --- getUserRole -----------------------------------------------------------

describe("getUserRole", () => {
  it("returns the profile's role when one exists", async () => {
    mockProfileRole("content_moderator");
    await expect(getUserRole("user-1")).resolves.toBe("content_moderator");
  });

  it("returns null when there's no profile row", async () => {
    mockProfileRole(null);
    await expect(getUserRole("user-1")).resolves.toBeNull();
  });
});

// --- assertCanChangeProfileRole (mirrors lock_profile_role_field) ---------

describe("assertCanChangeProfileRole", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(assertCanChangeProfileRole()).rejects.toBeInstanceOf(AuthError);
  });

  it("throws ForbiddenError for a signed-in non-super_admin", async () => {
    mockSessionUser({ id: "user-1" });
    mockProfileRole("regional_admin");
    await expect(assertCanChangeProfileRole()).rejects.toBeInstanceOf(ForbiddenError);
  });

  it("resolves for a super_admin", async () => {
    mockSessionUser({ id: "user-1" });
    mockProfileRole("super_admin");
    await expect(assertCanChangeProfileRole()).resolves.toEqual({
      user: { id: "user-1" },
      role: "super_admin",
    });
  });
});

// --- assertCanVerifyAttraction / assertCanVerifyRestaurant ----------------
//
// Both mirror a separate live trigger (`lock_attraction_verification_fields`
// / `lock_restaurant_verification_fields`) but share the exact same role
// list, so they're tested with the same table.

describe.each([
  ["assertCanVerifyAttraction", assertCanVerifyAttraction],
  ["assertCanVerifyRestaurant", assertCanVerifyRestaurant],
] as const)("%s", (_name, assertFn) => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(assertFn()).rejects.toBeInstanceOf(AuthError);
  });

  it("throws ForbiddenError for a signed-in traveler", async () => {
    mockSessionUser({ id: "user-1" });
    mockProfileRole("traveler");
    await expect(assertFn()).rejects.toBeInstanceOf(ForbiddenError);
  });

  it.each(["content_moderator", "regional_admin", "super_admin"] as const)(
    "resolves for a %s",
    async (role) => {
      mockSessionUser({ id: "user-1" });
      mockProfileRole(role);
      await expect(assertFn()).resolves.toEqual({ user: { id: "user-1" }, role });
    },
  );
});

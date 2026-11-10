// Integration coverage for the bug described in this branch's motivating
// request: `updateUserRole`/`setAttractionVerification`/
// `setRestaurantVerification` previously ran their writes over a plain
// Prisma connection, which the live `lock_profile_role_field` /
// `lock_attraction_verification_fields` / `lock_restaurant_verification_fields`
// triggers (see prisma/db-notes.sql §2) see as having `auth.uid() = NULL` —
// so every one of these writes was silently reverted by the trigger even
// for a genuinely authorized super_admin/moderator, while the surrounding
// transaction still committed "successfully" (and, for `updateUserRole`,
// still wrote an `admin_action_log` row describing a change that never
// actually happened).
//
// `lib/server/profiles.test.ts` / `attractions.test.ts` / `restaurants.test.ts`
// mock Prisma entirely, so they can assert "we called `prisma.profile.update`
// with the right arguments" but can never observe whether a trigger then
// reverted it. This file runs the real functions against a real Postgres
// database with the actual trigger SQL installed (see
// prisma/test-support/*.sql and .github/workflows/nextjs-ci.yml's
// `db-trigger-integration` job for how that database is built) — it would
// have FAILED against the pre-`runAsUser` version of these three functions
// and passes now, which is the whole point.
//
// `assertIntegrationTestDatabaseIsSafe()` below is a hard, non-override-able
// refusal (same shape as prisma/seed.ts's own guard) if `DATABASE_URL` isn't
// a loopback address or looks like the live project — this file performs
// real writes and must never be able to run anywhere else.
import { describe, it, expect, beforeEach, vi } from "vitest";
import type { User } from "@supabase/supabase-js";
import { assertIntegrationTestDatabaseIsSafe } from "./db-guard";
import { resetIntegrationDatabase, seedAttraction, seedProfile, seedRestaurant } from "./fixtures";

assertIntegrationTestDatabaseIsSafe();

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { ForbiddenError } from "@/lib/auth/permissions";
import { updateUserRole } from "@/lib/server/profiles";
import { setAttractionVerification } from "@/lib/server/attractions";
import { setRestaurantVerification } from "@/lib/server/restaurants";

function mockSessionUser(userId: string) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user: { id: userId } as User } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub, only `auth.getUser()` is exercised
  } as any);
}

beforeEach(async () => {
  vi.clearAllMocks();
  await resetIntegrationDatabase();
});

describe("updateUserRole against a real Postgres + lock_profile_role_field trigger", () => {
  it("sticks for a super_admin, and writes exactly one admin_action_log row", async () => {
    const adminId = await seedProfile("super_admin");
    const targetId = await seedProfile("traveler");
    mockSessionUser(adminId);

    const result = await updateUserRole(targetId, "content_moderator");
    expect(result.role).toBe("content_moderator");

    // Read back independently of updateUserRole's own return value — this is
    // the actual regression check: before `runAsUser`, the trigger reverted
    // this UPDATE and this re-read would still show "traveler".
    const reread = await prisma.profile.findUnique({ where: { id: targetId } });
    expect(reread?.role).toBe("content_moderator");

    const logs = await prisma.adminActionLog.findMany({ where: { targetProfileId: targetId } });
    expect(logs).toHaveLength(1);
    expect(logs[0]).toMatchObject({
      actorId: adminId,
      actionType: "assign_role",
      oldRole: "traveler",
      newRole: "content_moderator",
    });
  });

  it("rejects a non-admin's attempt before it reaches the database — role unchanged, no audit row", async () => {
    const actorId = await seedProfile("traveler");
    const targetId = await seedProfile("traveler");
    mockSessionUser(actorId);

    await expect(updateUserRole(targetId, "content_moderator")).rejects.toBeInstanceOf(
      ForbiddenError,
    );

    const reread = await prisma.profile.findUnique({ where: { id: targetId } });
    expect(reread?.role).toBe("traveler");
    expect(await prisma.adminActionLog.count()).toBe(0);
  });
});

describe("setAttractionVerification against a real Postgres + lock_attraction_verification_fields trigger", () => {
  it("sticks for a content_moderator", async () => {
    const modId = await seedProfile("content_moderator");
    const ownerId = await seedProfile("traveler");
    const attractionId = await seedAttraction(ownerId);
    mockSessionUser(modId);

    const result = await setAttractionVerification(attractionId, "verified");
    expect(result.verificationStatus).toBe("verified");
    expect(result.verifiedBy).toBe(modId);
    expect(result.verifiedAt).toBeInstanceOf(Date);

    const reread = await prisma.attraction.findUnique({ where: { id: attractionId } });
    expect(reread?.verificationStatus).toBe("verified");
    expect(reread?.verifiedBy).toBe(modId);
    expect(reread?.verifiedAt).toBeInstanceOf(Date);
  });

  it("rejects a non-moderator's attempt before it reaches the database — listing unchanged", async () => {
    const actorId = await seedProfile("traveler");
    const ownerId = await seedProfile("traveler");
    const attractionId = await seedAttraction(ownerId);
    mockSessionUser(actorId);

    await expect(setAttractionVerification(attractionId, "verified")).rejects.toBeInstanceOf(
      ForbiddenError,
    );

    const reread = await prisma.attraction.findUnique({ where: { id: attractionId } });
    expect(reread?.verificationStatus).toBe("pending");
    expect(reread?.verifiedBy).toBeNull();
  });
});

describe("setRestaurantVerification against a real Postgres + lock_restaurant_verification_fields trigger", () => {
  it("sticks for a regional_admin", async () => {
    const adminId = await seedProfile("regional_admin");
    const ownerId = await seedProfile("traveler");
    const restaurantId = await seedRestaurant(ownerId);
    mockSessionUser(adminId);

    const result = await setRestaurantVerification(restaurantId, "verified");
    expect(result.verificationStatus).toBe("verified");
    expect(result.verifiedBy).toBe(adminId);
    expect(result.verifiedAt).toBeInstanceOf(Date);

    const reread = await prisma.restaurant.findUnique({ where: { id: restaurantId } });
    expect(reread?.verificationStatus).toBe("verified");
    expect(reread?.verifiedBy).toBe(adminId);
    expect(reread?.verifiedAt).toBeInstanceOf(Date);
  });

  it("rejects a non-moderator's attempt before it reaches the database — listing unchanged", async () => {
    const actorId = await seedProfile("traveler");
    const ownerId = await seedProfile("traveler");
    const restaurantId = await seedRestaurant(ownerId);
    mockSessionUser(actorId);

    await expect(setRestaurantVerification(restaurantId, "verified")).rejects.toBeInstanceOf(
      ForbiddenError,
    );

    const reread = await prisma.restaurant.findUnique({ where: { id: restaurantId } });
    expect(reread?.verificationStatus).toBe("pending");
    expect(reread?.verifiedBy).toBeNull();
  });
});

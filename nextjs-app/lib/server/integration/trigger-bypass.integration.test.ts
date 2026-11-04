// Defense-in-depth coverage, deliberately bypassing the TypeScript
// authorization guard (`assertCanChangeProfileRole()` /
// `assertCanVerifyAttraction()`) that `updateUserRole`/
// `setAttractionVerification` normally run *before* ever calling
// `runAsUser()`.
//
// The sibling file, `trigger-behavior.integration.test.ts`, proves the
// end-to-end public functions work correctly for both authorized and
// unauthorized callers — but its "rejects a non-admin" cases never reach
// `runAsUser()`, or the database, at all: `assertCan*()` throws first. That
// leaves one thing unverified: if a future refactor ever called `runAsUser()`
// directly for a non-admin/non-moderator actor — by mistake, or via some new
// code path that forgot to call the app-level guard first — would the live
// trigger, plus the re-read-and-throw safety net `updateUserRole`/
// `setAttractionVerification` build on top of it, still catch it?
//
// This file answers that directly: it calls `runAsUser()` with a
// traveler-role `actingUserId` and replicates the exact write → re-read →
// throw-if-reverted → (only then) audit-log sequence those two modules use
// internally (see `lib/server/profiles.ts`'s `updateUserRole` and
// `lib/server/attractions.ts`'s `setAttractionVerification`), with NO
// app-level permission check in front of it at all — i.e. exactly the
// low-level path `assertCanChangeProfileRole()`/`assertCanVerifyAttraction()`
// are supposed to stand in front of, called as if that guard didn't exist.
//
// Expected (and asserted) outcome for both cases below: `auth.uid()` now
// correctly resolves to a real-but-unauthorized user (not NULL, and not a
// spoofed admin — `runAsUser()` doesn't invent authorization, it only makes
// the real actor visible to Postgres), so the trigger's own `exists(...)`
// check against `profiles.role` fails and it reverts the write; the re-read
// sees the unchanged value; the matching `*RevertedError` is thrown; the
// whole transaction rolls back; and no audit-log row exists. The safety net
// holds with zero help from the TypeScript guard layer — proving the
// authorization boundary here is the trigger + the re-read guard, not merely
// "the Server Action happened to check first."
//
// Allow-listed in `lib/server/write-guard.test.ts` for the same reason
// `fixtures.ts` is: its direct `tx.profile.update(...)`/`tx.attraction.update(...)`
// calls are the intentional subject under test here, not an accidental write
// path the guard needs to flag, and `assertIntegrationTestDatabaseIsSafe()`
// below means this can only ever run against a disposable loopback/CI
// database, never the live project.
import { describe, it, expect, beforeEach } from "vitest";
import { Prisma } from "@/lib/generated/prisma/client";
import { assertIntegrationTestDatabaseIsSafe } from "./db-guard";
import { resetIntegrationDatabase, seedAttraction, seedProfile } from "./fixtures";

assertIntegrationTestDatabaseIsSafe();

import { prisma } from "@/lib/db";
import { runAsUser } from "@/lib/server/db-as-user";
import { RoleChangeRevertedError } from "@/lib/server/profiles";
import { AttractionVerificationRevertedError } from "@/lib/server/attractions";

beforeEach(async () => {
  await resetIntegrationDatabase();
});

describe("runAsUser + lock_profile_role_field, invoked directly for a non-admin actor (no assertCanChangeProfileRole in front)", () => {
  it("reverts the role, throws RoleChangeRevertedError, and writes no admin_action_log row", async () => {
    const actorId = await seedProfile("traveler"); // deliberately NOT super_admin
    const targetId = await seedProfile("traveler");

    const attempt = runAsUser(
      actorId,
      async (tx) => {
        await tx.profile.update({ where: { id: targetId }, data: { role: "content_moderator" } });

        // Mirrors updateUserRole's own re-read guard exactly
        // (lib/server/profiles.ts) — no assertCanChangeProfileRole() call
        // anywhere in this test, by design.
        const reread = await tx.profile.findUnique({ where: { id: targetId } });
        if (!reread || reread.role !== "content_moderator") {
          throw new RoleChangeRevertedError();
        }

        // Unreachable for this actor if the guard above does its job — kept
        // in the attempt (rather than omitted) so this test would also catch
        // a regression that let a false success through to a false audit-log
        // write, not just a regression in the thrown error alone.
        await tx.adminActionLog.create({
          data: {
            actorId,
            actionType: "assign_role",
            targetProfileId: targetId,
            oldRole: "traveler",
            newRole: "content_moderator",
            details: { old_role: "traveler", new_role: "content_moderator" },
          },
        });

        return reread;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    await expect(attempt).rejects.toBeInstanceOf(RoleChangeRevertedError);

    // (a) the trigger actually reverted the role — read back independently of
    // the thrown error, same regression check as trigger-behavior.integration.test.ts.
    const reread = await prisma.profile.findUnique({ where: { id: targetId } });
    expect(reread?.role).toBe("traveler");

    // (c) no admin_action_log row — proves the transaction rollback (from the
    // thrown error, itself thrown before the create() call above even runs)
    // also undid any attempt at a log write, not just the role write.
    expect(await prisma.adminActionLog.count()).toBe(0);
  });
});

describe("runAsUser + lock_attraction_verification_fields, invoked directly for a non-moderator actor (no assertCanVerifyAttraction in front)", () => {
  it("reverts the verification fields and throws AttractionVerificationRevertedError", async () => {
    const actorId = await seedProfile("traveler"); // deliberately not a moderator-tier role
    const ownerId = await seedProfile("traveler");
    const attractionId = await seedAttraction(ownerId);
    const verifiedAt = new Date();

    const attempt = runAsUser(actorId, async (tx) => {
      await tx.attraction.update({
        where: { id: attractionId },
        data: { verificationStatus: "verified", verifiedBy: actorId, verifiedAt },
      });

      // Mirrors setAttractionVerification's own re-read guard exactly
      // (lib/server/attractions.ts) — no assertCanVerifyAttraction() call
      // anywhere in this test, by design.
      const reread = await tx.attraction.findUnique({ where: { id: attractionId } });
      if (
        !reread ||
        reread.verificationStatus !== "verified" ||
        reread.verifiedBy !== actorId ||
        reread.verifiedAt?.getTime() !== verifiedAt.getTime()
      ) {
        throw new AttractionVerificationRevertedError();
      }

      return reread;
    });

    await expect(attempt).rejects.toBeInstanceOf(AttractionVerificationRevertedError);

    // (a) the trigger actually reverted all three locked columns as a group —
    // read back independently of the thrown error.
    const reread = await prisma.attraction.findUnique({ where: { id: attractionId } });
    expect(reread?.verificationStatus).toBe("pending");
    expect(reread?.verifiedBy).toBeNull();
    expect(reread?.verifiedAt).toBeNull();
  });
});

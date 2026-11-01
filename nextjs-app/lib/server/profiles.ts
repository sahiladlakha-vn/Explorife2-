import "server-only";
import { cache } from "react";
import { prisma } from "@/lib/db";
import { Prisma } from "@/lib/generated/prisma/client";
import {
  PROFILE_ROLE_CHANGE_ROLES,
  ForbiddenError,
  assertCanChangeProfileRole,
  getUserRole,
  requireUser,
  type Role,
} from "@/lib/auth/permissions";
import { warnStrippedFields } from "./audit-log";

/**
 * The ONLY module allowed to call `prisma.profile.create/update/updateMany/
 * upsert/delete/deleteMany` — enforced by
 * `lib/server/write-guard.test.ts`, which scans the rest of the codebase for
 * direct calls and fails the suite if it finds any. Every other file must go
 * through the functions exported here.
 *
 * Mirrors the live `profiles_lock_role_field` BEFORE UPDATE trigger (see
 * `prisma/db-notes.sql` §2, function `lock_profile_role_field()`):
 *
 *   if new.role <> old.role and not exists (
 *     select 1 from public.profiles where id = auth.uid() and role = 'super_admin'
 *   ) then
 *     new.role := old.role;  -- silently revert just the role column
 *   end if;
 *
 * The trigger reverts *only* `role` and lets the rest of the UPDATE proceed —
 * it never fails the whole write. `updateProfile` below reproduces that exact
 * outcome (unauthorized role changes are dropped, everything else still
 * saves) rather than rejecting the whole request, which is why it strips
 * `role` instead of throwing when the caller can't set it. See the
 * module-level caveat in `lib/auth/permissions.ts` for why the live trigger
 * itself no longer lets an *authorized* Prisma-issued role change through —
 * that's a separate, approval-gated DB change (MIGRATION_PLAN.md §6 Risk #3),
 * not something this module can fix.
 */

/** Fields any profile owner (or super_admin) may freely edit. */
export interface ProfileWritePatch {
  name?: string;
  avatarUrl?: string | null;
  bio?: string;
  city?: string;
  country?: string;
  languages?: string[];
  displayName?: string | null;
  privacyShowGps?: boolean;
  privacyBlurMaps?: boolean;
  username?: string | null;
  /**
   * Accepted on the patch type so a single call site can attempt a combined
   * profile-edit + role-change in one request, but see `updateProfile`'s
   * stripping behavior below for what happens when the caller isn't
   * authorized to actually set it.
   */
  role?: Role;
}

/**
 * General-purpose profile editor. Requires a session; only the profile's own
 * owner or a `super_admin` may edit a given profile at all — a baseline
 * ownership check this module needs regardless of the `role`-locking
 * behavior below, since there's otherwise no gate at all on
 * `prisma.profile.update`. The non-owner gate deliberately reuses
 * `PROFILE_ROLE_CHANGE_ROLES` (super_admin only) rather than the broader
 * `ADMIN_ROLES` list, to match the live `profiles_update_admin` RLS policy
 * (`is_super_admin()`) exactly — see MIGRATION_PLAN.md's RLS-parity review:
 * `content_moderator`/`regional_admin`/`finance_admin` have no RLS grant to
 * edit someone *else's* profile row at all, only `super_admin` does.
 *
 * If `patch.role` is present, `role` is only kept when
 * `assertCanChangeProfileRole()` succeeds for the current session; otherwise
 * it's silently dropped (not thrown) and the rest of the patch is still
 * applied, matching the trigger's "revert just this column" behavior
 * described above.
 */
export async function updateProfile(targetUserId: string, patch: ProfileWritePatch) {
  const actor = await requireUser();
  const isSelf = actor.id === targetUserId;
  if (!isSelf) {
    const actorRole = await getUserRole(actor.id);
    if (!actorRole || !PROFILE_ROLE_CHANGE_ROLES.includes(actorRole)) {
      throw new ForbiddenError("You can only edit your own profile.");
    }
  }

  const safePatch: ProfileWritePatch = { ...patch };
  if (safePatch.role !== undefined) {
    try {
      await assertCanChangeProfileRole();
    } catch {
      delete safePatch.role;
      warnStrippedFields({
        userId: actor.id,
        table: "profiles",
        recordId: targetUserId,
        strippedFields: ["role"],
      });
    }
  }

  return prisma.profile.update({ where: { id: targetUserId }, data: safePatch });
}

/** Thrown when two concurrent role changes collide under Serializable isolation. */
export class ConcurrentRoleChangeError extends Error {
  constructor(message = "Roles were changed at the same time — please try again.") {
    super(message);
    this.name = "ConcurrentRoleChangeError";
  }
}

/**
 * Dedicated role-change path — full TypeScript port of the live
 * `admin_update_user_role` SECURITY DEFINER RPC (`explorife_schema_export.sql`),
 * including every guard it has, in the same order:
 *
 *   1. `insufficient_privilege` — only a super_admin may call this at all.
 *      Ported as `assertCanChangeProfileRole()` below (unchanged from before
 *      this pass).
 *   2. `profile not found: %` — the target has no `profiles` row.
 *   3. `cannot assign a role to an anonymous guest session` — the target's
 *      Supabase Auth user has `is_anonymous = true`. Ported by reading
 *      `User.isAnonymous` (see that field's doc comment in
 *      `prisma/schema.prisma`) via a plain join on `tx.profile.findUnique`'s
 *      `include`, in the SAME query as guard 2's existence check and INSIDE
 *      the Serializable transaction below — unlike the version of this guard
 *      from the previous pass, this is no longer a separate pre-transaction
 *      Supabase Admin API round-trip; it's one Prisma read, consistent with
 *      the rest of the guard chain's snapshot.
 *   4. `if v_old_role = p_new_role then return;` — same-role is a silent
 *      no-op: no update, no `admin_action_log` row. Ported as an early
 *      `return` inside the transaction once `oldRole` is known.
 *   5. `cannot remove the last super_admin account's super_admin role` — the
 *      RPC's exact condition is `p_target_id = auth.uid() AND p_new_role <>
 *      'super_admin' AND (select count(*) from profiles where role =
 *      'super_admin') <= 1`, i.e. this only ever fires on SELF-demotion: if
 *      there's more than one super_admin, demoting any single one (including
 *      a different super_admin) is fine, and only a self-targeting demotion
 *      can ever reduce the super_admin count when there's just one left.
 *      Ported with the identical condition below.
 *
 * `insufficient_privilege` aside, no other guard exists in the live RPC —
 * this is the complete set.
 *
 * Also writes an `admin_action_log` row in the same transaction as the role
 * update (added in the hardening pass before this one), matching what the
 * live RPC records: `actor_id`, `action_type` (`"assign_role"`),
 * `target_profile_id`, `old_role`/`new_role`, and a `details` jsonb mirroring
 * the old/new role pair.
 *
 * Concurrency: guard 5 above has a real race in the *original* SQL RPC too —
 * if there are exactly two super_admins and both simultaneously self-demote
 * (two separate calls, each reading `count(*) = 2` before either commits),
 * neither call's guard fires and both succeed, leaving zero super_admins.
 * This is the classic Postgres "write skew" anomaly (same shape as the
 * textbook "two doctors going off call" example). Per your request, this is
 * closed here — not in the original RPC — by running the whole guard+update
 * in a `Serializable`-isolation transaction: Postgres's serializable
 * snapshot isolation detects the overlapping read (the `super_admin` count)
 * plus overlapping write (both transactions touching rows matching that same
 * predicate) and aborts one of the two with a serialization-failure error
 * (Prisma surfaces this as `P2034`) rather than letting both commit. An
 * explicit `SELECT ... FOR UPDATE` row lock was the other option you
 * mentioned, but it wouldn't actually close this specific race: the two
 * conflicting transactions target two DIFFERENT profile rows (each
 * self-demoting a different super_admin), so a lock scoped to "the row being
 * updated" never overlaps between them. Serializable isolation is the
 * version of this fix that actually covers the cross-row case.
 *
 * A `P2034` (the "loser" of the race) is caught at this function's boundary
 * and re-thrown as `ConcurrentRoleChangeError`, a clear "please retry"
 * message instead of a raw Prisma error code reaching an admin's screen. No
 * automatic retry is attempted here — re-running the whole guard chain
 * against fresh data is a reasonable follow-up but a separate, larger
 * decision than "surface a clear error," so it's flagged rather than added.
 * Any other error (including the guards' own thrown `Error`/`ForbiddenError`
 * above) propagates unchanged.
 */
export async function updateUserRole(targetUserId: string, role: Role) {
  const { user: actor } = await assertCanChangeProfileRole();

  try {
    return await prisma.$transaction(
      async (tx) => {
        const target = await tx.profile.findUnique({
          where: { id: targetUserId },
          include: { user: { select: { isAnonymous: true } } },
        });
        if (!target) {
          throw new Error(`Profile ${targetUserId} not found.`);
        }

        if (target.user.isAnonymous ?? false) {
          throw new ForbiddenError("Cannot assign a role to an anonymous guest session.");
        }

        const oldRole = target.role;
        if (oldRole === role) {
          return target;
        }

        if (targetUserId === actor.id && role !== "super_admin") {
          const superAdminCount = await tx.profile.count({ where: { role: "super_admin" } });
          if (superAdminCount <= 1) {
            throw new ForbiddenError(
              "Cannot remove the last super_admin account's super_admin role.",
            );
          }
        }

        const updated = await tx.profile.update({ where: { id: targetUserId }, data: { role } });

        await tx.adminActionLog.create({
          data: {
            actorId: actor.id,
            actionType: "assign_role",
            targetProfileId: targetUserId,
            oldRole,
            newRole: role,
            details: { old_role: oldRole, new_role: role },
          },
        });

        return updated;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      throw new ConcurrentRoleChangeError();
    }
    throw err;
  }
}

/**
 * Read-only — for the Step 4 shared `/profile` layout's `ProfileHeader`
 * (MIGRATION_PLAN.md §7). Not subject to the write-guard rule at the top of
 * this file (that rule only covers mutating `prisma.profile.*` calls);
 * grouped here anyway since it's profile-domain data. Wrapped in `cache()` so
 * the layout can call it without worrying about a second query if a leaf
 * page ever also needs it within the same request.
 */
export const getProfileHeaderData = cache(async function getProfileHeaderData(userId: string) {
  const [profile, leaderboardEntry] = await Promise.all([
    prisma.profile.findUnique({ where: { id: userId } }),
    prisma.leaderboard.findUnique({ where: { userId } }),
  ]);
  return { profile, leaderboardEntry };
});

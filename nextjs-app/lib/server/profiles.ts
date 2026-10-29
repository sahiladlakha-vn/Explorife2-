import "server-only";
import { prisma } from "@/lib/db";
import {
  ADMIN_ROLES,
  ForbiddenError,
  assertCanChangeProfileRole,
  getUserRole,
  requireUser,
  type Role,
} from "@/lib/auth/permissions";

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

/** Fields any profile owner (or admin-tier role) may freely edit. */
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
 * owner or an admin-tier role (`ADMIN_ROLES`) may edit a given profile at
 * all — a baseline ownership check this module needs regardless of the
 * `role`-locking behavior below, since there's otherwise no gate at all on
 * `prisma.profile.update`. If `patch.role` is present, `role` is only kept
 * when `assertCanChangeProfileRole()` succeeds for the current session;
 * otherwise it's silently dropped (not thrown) and the rest of the patch is
 * still applied, matching the trigger's "revert just this column" behavior
 * described above.
 */
export async function updateProfile(targetUserId: string, patch: ProfileWritePatch) {
  const actor = await requireUser();
  const isSelf = actor.id === targetUserId;
  if (!isSelf) {
    const actorRole = await getUserRole(actor.id);
    if (!actorRole || !ADMIN_ROLES.includes(actorRole)) {
      throw new ForbiddenError("You can only edit your own profile.");
    }
  }

  const safePatch: ProfileWritePatch = { ...patch };
  if (safePatch.role !== undefined) {
    try {
      await assertCanChangeProfileRole();
    } catch {
      delete safePatch.role;
    }
  }

  return prisma.profile.update({ where: { id: targetUserId }, data: safePatch });
}

/**
 * Dedicated role-change path — mirrors `updateUserRole()` from
 * MIGRATION_PLAN.md §3a. Unlike `updateProfile` above, this throws
 * (AuthError/ForbiddenError) when the caller isn't a super_admin, since
 * setting the role is the entire point of calling it — there's no "rest of
 * the patch" to fall back to.
 */
export async function updateUserRole(targetUserId: string, role: Role) {
  await assertCanChangeProfileRole();
  return prisma.profile.update({ where: { id: targetUserId }, data: { role } });
}

import "server-only";
import { prisma } from "@/lib/db";
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

/**
 * Dedicated role-change path — mirrors `updateUserRole()` from
 * MIGRATION_PLAN.md §3a. Unlike `updateProfile` above, this throws
 * (AuthError/ForbiddenError) when the caller isn't a super_admin, since
 * setting the role is the entire point of calling it — there's no "rest of
 * the patch" to fall back to.
 *
 * Also writes an `admin_action_log` row in the same transaction as the role
 * update, matching what the live `admin_update_user_role` SECURITY DEFINER
 * RPC recorded (`supabase/migrations/20260925000300_admin_update_user_role_
 * log_columns.sql`): `actor_id` (the acting super_admin), `action_type`
 * (`"assign_role"`), `target_profile_id`, `old_role`/`new_role`, and a
 * `details` jsonb mirroring the old/new role pair. `old_role` is read inside
 * the same transaction as the update to avoid a race against a concurrent
 * role change.
 *
 * Scope note: this only ports the log-write behavior, which is what was
 * asked for. The live RPC also has several additional guards this function
 * does NOT reproduce — a target-not-found check, a rejection of
 * anonymous/guest targets, a same-role no-op short-circuit, and a
 * last-super-admin-demotion guard. Flagging these as a gap rather than
 * silently porting or silently omitting them: they're a separate scope
 * decision, not something implied by "write the log row."
 */
export async function updateUserRole(targetUserId: string, role: Role) {
  const { user: actor } = await assertCanChangeProfileRole();

  return prisma.$transaction(async (tx) => {
    const target = await tx.profile.findUnique({
      where: { id: targetUserId },
      select: { role: true },
    });
    const oldRole = target?.role ?? null;

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
  });
}

import "server-only";
import { prisma } from "@/lib/db";
import {
  ADMIN_ROLES,
  ForbiddenError,
  assertCanVerifyAttraction,
  getUserRole,
  requireUser,
} from "@/lib/auth/permissions";

/**
 * The ONLY module allowed to call `prisma.attraction.create/update/
 * updateMany/upsert/delete/deleteMany` — enforced by
 * `lib/server/write-guard.test.ts`, which scans the rest of the codebase for
 * direct calls and fails the suite if it finds any. Every other file must go
 * through the functions exported here.
 *
 * Mirrors the live `attractions_lock_verification_fields` BEFORE UPDATE
 * trigger (see `prisma/db-notes.sql` §2, function
 * `lock_attraction_verification_fields()`):
 *
 *   if not exists (
 *     select 1 from public.profiles
 *     where profiles.id = auth.uid()
 *       and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
 *   ) then
 *     new.verification_status := old.verification_status;
 *     new.verified_by := old.verified_by;
 *     new.verified_at := old.verified_at;
 *   end if;
 *   new.updated_at := now();
 *
 * The trigger reverts only the three verification columns (as a group) and
 * lets the rest of the UPDATE proceed — including, notably, an owner editing
 * their own listing's `name`/`description`/etc. It never fails the whole
 * write. `updateAttraction` below reproduces that: unauthorized attempts to
 * set the verification fields are dropped (not thrown), and the rest of the
 * patch — including an owner's edits to their own non-locked fields — still
 * saves. `updated_at` is left to Prisma's own `@updatedAt`/caller-supplied
 * value rather than hardcoded here, since that part of the trigger isn't
 * `auth.uid()`-dependent (see `prisma/db-notes.sql` §3) and schema.prisma
 * already models it.
 */

/** Fields the listing owner (or admin-tier role) may freely edit. */
export interface AttractionWritePatch {
  name?: string;
  category?: string;
  gallery?: string[];
  address?: string;
  latitude?: number;
  longitude?: number;
  openingHours?: string;
  entryFeeType?: string;
  entryFeeAmount?: number | null;
  currency?: string;
  description?: string;
  certificationUrls?: string[];
  recommendedDuration?: string | null;
  /**
   * Accepted on the patch type so a single call site (e.g. a moderator
   * dashboard) can attempt a combined listing-edit + verification update in
   * one request, but see `updateAttraction`'s stripping behavior below for
   * what happens when the caller isn't authorized to actually set these.
   */
  verificationStatus?: string;
  verifiedBy?: string | null;
  verifiedAt?: Date | null;
}

/**
 * General-purpose attraction editor. Requires a session; only the listing's
 * owner or an admin-tier role (`ADMIN_ROLES`) may edit a given attraction at
 * all. If the patch touches any of `verificationStatus`/`verifiedBy`/
 * `verifiedAt`, all three are only kept when `assertCanVerifyAttraction()`
 * succeeds for the current session; otherwise all three are silently dropped
 * (not thrown, matching the trigger reverting them as a group) and the rest
 * of the patch — including the owner's own non-locked edits — is still
 * applied.
 */
export async function updateAttraction(attractionId: string, patch: AttractionWritePatch) {
  const actor = await requireUser();
  const attraction = await prisma.attraction.findUnique({
    where: { id: attractionId },
    select: { ownerId: true },
  });
  if (!attraction) {
    throw new Error(`Attraction ${attractionId} not found.`);
  }

  const isOwner = actor.id === attraction.ownerId;
  if (!isOwner) {
    const actorRole = await getUserRole(actor.id);
    if (!actorRole || !ADMIN_ROLES.includes(actorRole)) {
      throw new ForbiddenError("You can only edit your own listing.");
    }
  }

  const safePatch: AttractionWritePatch = { ...patch };
  const touchesVerificationFields =
    safePatch.verificationStatus !== undefined ||
    safePatch.verifiedBy !== undefined ||
    safePatch.verifiedAt !== undefined;

  if (touchesVerificationFields) {
    try {
      await assertCanVerifyAttraction();
    } catch {
      delete safePatch.verificationStatus;
      delete safePatch.verifiedBy;
      delete safePatch.verifiedAt;
    }
  }

  return prisma.attraction.update({ where: { id: attractionId }, data: safePatch });
}

/**
 * Dedicated verification path — mirrors `verifyAttraction()`/
 * `retractAttraction()` from MIGRATION_PLAN.md §3a. Unlike `updateAttraction`
 * above, this throws (AuthError/ForbiddenError) when the caller isn't a
 * content_moderator/regional_admin/super_admin, since setting verification
 * is the entire point of calling it.
 */
export async function setAttractionVerification(
  attractionId: string,
  status: string,
  verifiedBy: string | null,
  verifiedAt: Date | null,
) {
  await assertCanVerifyAttraction();
  return prisma.attraction.update({
    where: { id: attractionId },
    data: { verificationStatus: status, verifiedBy, verifiedAt },
  });
}

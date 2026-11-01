import "server-only";
import { prisma } from "@/lib/db";
import {
  ForbiddenError,
  VERIFICATION_MODERATOR_ROLES,
  assertCanVerifyRestaurant,
  getUserRole,
  requireUser,
} from "@/lib/auth/permissions";
import { warnStrippedFields } from "./audit-log";

/**
 * The ONLY module allowed to call `prisma.restaurant.create/update/
 * updateMany/upsert/delete/deleteMany` — enforced by
 * `lib/server/write-guard.test.ts`, which scans the rest of the codebase for
 * direct calls and fails the suite if it finds any. Every other file must go
 * through the functions exported here.
 *
 * Mirrors the live `restaurants_lock_verification_fields` BEFORE UPDATE
 * trigger (see `prisma/db-notes.sql` §2, function
 * `lock_restaurant_verification_fields()`), which is identical in shape to
 * `lock_attraction_verification_fields()` (same role list, same three
 * columns, same "revert the group, let the rest of the UPDATE proceed"
 * behavior) — see `lib/server/attractions.ts` for the full trigger SQL and
 * rationale; it applies here unchanged, just against `restaurants`.
 */

/** Fields the listing owner (or admin-tier role) may freely edit. */
export interface RestaurantWritePatch {
  name?: string;
  category?: string;
  cuisineType?: string[];
  priceRange?: string;
  gallery?: string[];
  address?: string;
  latitude?: number;
  longitude?: number;
  phone?: string;
  openingHours?: string;
  dietaryOptions?: string[];
  reservationOption?: boolean;
  businessLicenseUrl?: string | null;
  /**
   * Accepted on the patch type so a single call site (e.g. a moderator
   * dashboard) can attempt a combined listing-edit + verification update in
   * one request, but see `updateRestaurant`'s stripping behavior below for
   * what happens when the caller isn't authorized to actually set these.
   */
  verificationStatus?: string;
  verifiedBy?: string | null;
  verifiedAt?: Date | null;
}

/**
 * General-purpose restaurant editor. Requires a session; only the listing's
 * owner or a verification-moderator-tier role (`VERIFICATION_MODERATOR_ROLES`
 * — `content_moderator`/`regional_admin`/`super_admin`) may edit a given
 * restaurant at all. This deliberately reuses the same role list as the
 * verification gate below rather than the broader `ADMIN_ROLES`, to match the
 * live `"admins can update any restaurant"` RLS policy exactly — see
 * MIGRATION_PLAN.md's RLS-parity review: `finance_admin` has no RLS grant to
 * edit someone *else's* restaurant row at all.
 *
 * If the patch touches any of `verificationStatus`/`verifiedBy`/
 * `verifiedAt`, all three are only kept when `assertCanVerifyRestaurant()`
 * succeeds for the current session; otherwise all three are silently dropped
 * (not thrown, matching the trigger reverting them as a group) and the rest
 * of the patch — including the owner's own non-locked edits — is still
 * applied.
 */
export async function updateRestaurant(restaurantId: string, patch: RestaurantWritePatch) {
  const actor = await requireUser();
  const restaurant = await prisma.restaurant.findUnique({
    where: { id: restaurantId },
    select: { ownerId: true },
  });
  if (!restaurant) {
    throw new Error(`Restaurant ${restaurantId} not found.`);
  }

  const isOwner = actor.id === restaurant.ownerId;
  if (!isOwner) {
    const actorRole = await getUserRole(actor.id);
    if (!actorRole || !VERIFICATION_MODERATOR_ROLES.includes(actorRole)) {
      throw new ForbiddenError("You can only edit your own listing.");
    }
  }

  const safePatch: RestaurantWritePatch = { ...patch };
  const touchedVerificationFields = (
    ["verificationStatus", "verifiedBy", "verifiedAt"] as const
  ).filter((field) => safePatch[field] !== undefined);

  if (touchedVerificationFields.length > 0) {
    try {
      await assertCanVerifyRestaurant();
    } catch {
      delete safePatch.verificationStatus;
      delete safePatch.verifiedBy;
      delete safePatch.verifiedAt;
      warnStrippedFields({
        userId: actor.id,
        table: "restaurants",
        recordId: restaurantId,
        strippedFields: touchedVerificationFields,
      });
    }
  }

  return prisma.restaurant.update({ where: { id: restaurantId }, data: safePatch });
}

/**
 * Dedicated verification path — mirrors `verifyRestaurant()`/
 * `retractRestaurant()` from MIGRATION_PLAN.md §3a. Unlike `updateRestaurant`
 * above, this throws (AuthError/ForbiddenError) when the caller isn't a
 * content_moderator/regional_admin/super_admin, since setting verification
 * is the entire point of calling it.
 *
 * `verifiedBy`/`verifiedAt` are computed server-side from the acting session
 * (`verifiedBy` = the authenticated moderator's own id, `verifiedAt` =
 * `new Date()`) rather than accepted as caller-supplied input — a caller
 * must never be able to backdate a verification or attribute it to someone
 * else. `status` (`"verified"`/`"rejected"`/etc.) is still caller-supplied
 * since it isn't an identity/time claim.
 */
export async function setRestaurantVerification(restaurantId: string, status: string) {
  const { user } = await assertCanVerifyRestaurant();
  return prisma.restaurant.update({
    where: { id: restaurantId },
    data: { verificationStatus: status, verifiedBy: user.id, verifiedAt: new Date() },
  });
}

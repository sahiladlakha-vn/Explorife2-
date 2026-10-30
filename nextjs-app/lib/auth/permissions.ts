import "server-only";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";

/**
 * Centralized authorization — per MIGRATION_PLAN.md §0: Prisma connects with
 * elevated privileges and bypasses RLS, so every Server Action and Route
 * Handler that touches the database MUST call into this module rather than
 * assuming Postgres/RLS will reject anything. RLS stays enabled as
 * defense-in-depth, not as the primary gate.
 *
 * `import "server-only"` guards against this module (and the service-role
 * logic it will grow in Step 3+) ever being pulled into a client bundle.
 */

export class AuthError extends Error {
  constructor(message = "Authentication required.") {
    super(message);
    this.name = "AuthError";
  }
}

export class ForbiddenError extends Error {
  constructor(message = "You don't have permission to do this.") {
    super(message);
    this.name = "ForbiddenError";
  }
}

/** The current Supabase Auth session's user, or null if unauthenticated. */
export async function getCurrentUser(): Promise<User | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}

/**
 * Throws if there's no session — including an anonymous/guest session,
 * which is still a real Supabase Auth user (see MIGRATION_PLAN.md Risk #8).
 * Call first in any Server Action/Route Handler that requires sign-in.
 */
export async function requireUser(): Promise<User> {
  const user = await getCurrentUser();
  if (!user) throw new AuthError();
  return user;
}

/**
 * Convenience guard for routes/actions that must reject anonymous/guest
 * sessions specifically (anonymous Supabase users have `is_anonymous: true`
 * and no confirmed email) — e.g. anything equivalent to a
 * `requireAuth()` call site in §3a that isn't guest-eligible.
 */
export async function requireRealUser(): Promise<User> {
  const user = await requireUser();
  if (user.is_anonymous) {
    throw new ForbiddenError("This action isn't available for guest sessions.");
  }
  return user;
}

/**
 * Explicit alias for `getCurrentUser()` for call sites that treat "no
 * session" as a normal, valid state to render around (a guest view) rather
 * than an auth failure to throw on — e.g. `ProfileLayoutBody`/`TripLayoutBody`
 * (Step 5). Named separately from `getCurrentUser` so each call site reads
 * as a deliberate choice: "optional" (render a guest view) vs. the
 * throwing `requireUser`/`requireRealUser` guards above.
 */
export async function getOptionalUser(): Promise<User | null> {
  return getCurrentUser();
}

/**
 * Creates an anonymous Supabase Auth session for a visitor who doesn't have
 * one yet, so a write Server Action (save a gem, create a trip, ...) always
 * has a real `auth.uid()` to attach work to. Returns the existing user
 * unchanged if a session (guest or real) already exists — never creates a
 * second session on top of one that's already there.
 *
 * Deliberately NOT called from `proxy.ts`/`updateSession()` or from any
 * Server Component render path: both run on every request/page view
 * (including `<Link>` prefetches background-loading `/profile/*` from any
 * page that merely links there), which would fill `auth.users` with
 * anonymous rows for ordinary visitors and bots alike. The only safe place
 * to call this is inside a Server Action triggered by an explicit user
 * action that actually needs an identity — mirrors the Flutter app's
 * `requireAccount()` trigger point (sign_in_sheet.dart), just lazy instead
 * of eager. No call sites exist yet (Step 5 ships no write actions) — ready
 * for Step 6+.
 */
export async function ensureAnonymousSession(): Promise<User> {
  const existing = await getCurrentUser();
  if (existing) return existing;

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error || !data.user) {
    throw new AuthError("Could not start a guest session.");
  }
  return data.user;
}

// --- Role-based checks ------------------------------------------------
//
// `public.profiles.role` is the Prisma `Profile` model (`prisma/schema.prisma`,
// hand-built from live-DB introspection per MIGRATION_PLAN.md §3).
// `getUserRole` below is the one place that queries it — every function in
// this section is written against that stable signature so Step 3a's actual
// SECURITY-DEFINER ports (admin_update_user_role, verify_attraction, etc.,
// see MIGRATION_PLAN.md §3a) and Step 4's call sites don't need to change
// shape, just have their bodies filled in.

/** Mirrors ALLOWED_ROLES in supabase/functions/admin-create-user/index.ts. */
export type Role =
  | "traveler"
  | "guide"
  | "business_owner"
  | "content_moderator"
  | "regional_admin"
  | "super_admin"
  | "finance_admin";

/**
 * Roles treated as "an admin of some kind" by admin_list_users /
 * admin_role_counts per §3a. Provisional grouping, carried over from the
 * existing Settings -> Users page's admin-tier gating — confirm against the
 * live is_admin()/is_content_admin() SQL definitions when porting those
 * functions in Step 3a, rather than assuming this list is exhaustive.
 */
export const ADMIN_ROLES: readonly Role[] = [
  "super_admin",
  "finance_admin",
  "regional_admin",
  "content_moderator",
];

export async function getUserRole(userId: string): Promise<Role | null> {
  const profile = await prisma.profile.findUnique({
    where: { id: userId },
    select: { role: true },
  });
  return profile?.role ?? null;
}

/**
 * Throws AuthError if unauthenticated, ForbiddenError if authenticated but
 * missing the required role(s). Mirrors is_super_admin()/is_admin()'s own
 * role-check shape from the live SECURITY DEFINER functions (§3a) so the
 * ported TypeScript call sites read the same way the SQL did.
 */
export async function requireRole(
  allowed: Role | readonly Role[],
): Promise<{ user: User; role: Role }> {
  const user = await requireUser();
  const role = await getUserRole(user.id);
  const allowedList = Array.isArray(allowed) ? allowed : [allowed];
  if (!role || !allowedList.includes(role)) {
    throw new ForbiddenError();
  }
  return { user, role };
}

// --- Trigger-protection re-implementations -----------------------------
//
// Re-implements, in application code, the authorization logic of three live
// Postgres BEFORE UPDATE triggers documented in `prisma/db-notes.sql` §2 and
// MIGRATION_PLAN.md §3a: `lock_profile_role_field` (on `profiles`),
// `lock_attraction_verification_fields` (on `attractions`), and
// `lock_restaurant_verification_fields` (on `restaurants`).
//
// IMPORTANT — what this section does NOT fix (see MIGRATION_PLAN.md §3a /
// Risk #3, still an open question, not resolved here): those triggers key
// off `auth.uid()`, which Postgres's session-local `request.jwt.claims`
// setting only has a value when PostgREST sets it per-request. Prisma's
// direct connection never goes through PostgREST, so `auth.uid()` is always
// NULL in any session Prisma opens — which means each trigger's own
// `exists(...)` check deterministically fails and the trigger
// unconditionally REVERTS `profiles.role` / the verification fields back to
// their old values on every Prisma-issued UPDATE that touches them,
// regardless of whether the acting user was actually authorized. In other
// words: the functions below stop *unauthorized* requests from ever
// reaching Postgres (preserving the user-facing security property and
// failing fast with a clean 403), but they cannot make the live triggers let
// an *authorized* write through — that still silently reverts until the
// triggers themselves are altered/dropped on the live DB, which is a
// separate, approval-gated schema change tracked in MIGRATION_PLAN.md §6
// Risk #3, not performed by this module.
//
// Per the "No TS port — superseded" rows in MIGRATION_PLAN.md §3a: these
// three fields must only ever be written by the dedicated Server Actions
// that call the guards below (`updateUserRole()`,
// `verifyAttraction()`/`retractAttraction()`,
// `verifyRestaurant()`/`retractRestaurant()`) — no generic "edit profile" or
// "edit listing" action may accept `role`, `verificationStatus`,
// `verifiedBy`, or `verifiedAt` in its payload.

/** Roles allowed to change `profiles.role` — mirrors `lock_profile_role_field()`. */
export const PROFILE_ROLE_CHANGE_ROLES: readonly Role[] = ["super_admin"];

/**
 * Roles allowed to set attraction/restaurant verification fields — mirrors
 * `lock_attraction_verification_fields()` and
 * `lock_restaurant_verification_fields()`, which use an identical role list.
 */
export const VERIFICATION_MODERATOR_ROLES: readonly Role[] = [
  "content_moderator",
  "regional_admin",
  "super_admin",
];

/**
 * Pure predicate mirroring `lock_profile_role_field()`'s authorization
 * condition. Kept separate from `assertCanChangeProfileRole` below so the
 * decision logic itself is unit-testable without touching Supabase/Prisma.
 */
export function canChangeProfileRole(actingRole: Role | null): boolean {
  return actingRole !== null && PROFILE_ROLE_CHANGE_ROLES.includes(actingRole);
}

/**
 * Pure predicate mirroring `lock_attraction_verification_fields()` /
 * `lock_restaurant_verification_fields()`'s shared authorization condition.
 */
export function canSetListingVerification(actingRole: Role | null): boolean {
  return actingRole !== null && VERIFICATION_MODERATOR_ROLES.includes(actingRole);
}

/**
 * Throws AuthError if unauthenticated, ForbiddenError if authenticated but
 * not a super_admin. Mirrors the live `profiles_lock_role_field` trigger.
 * Call before any `prisma.profile.update()` that touches `role` — see the
 * module-level caveat above about what this does and doesn't fix.
 */
export async function assertCanChangeProfileRole(): Promise<{ user: User; role: Role }> {
  return requireRole(PROFILE_ROLE_CHANGE_ROLES);
}

/**
 * Throws AuthError if unauthenticated, ForbiddenError if authenticated but
 * not a content_moderator/regional_admin/super_admin. Mirrors the live
 * `attractions_lock_verification_fields` trigger. Call before any
 * `prisma.attraction.update()` that touches `verificationStatus`,
 * `verifiedBy`, or `verifiedAt` — see the module-level caveat above.
 */
export async function assertCanVerifyAttraction(): Promise<{ user: User; role: Role }> {
  return requireRole(VERIFICATION_MODERATOR_ROLES);
}

/**
 * Throws AuthError if unauthenticated, ForbiddenError if authenticated but
 * not a content_moderator/regional_admin/super_admin. Mirrors the live
 * `restaurants_lock_verification_fields` trigger. Call before any
 * `prisma.restaurant.update()` that touches `verificationStatus`,
 * `verifiedBy`, or `verifiedAt` — see the module-level caveat above.
 */
export async function assertCanVerifyRestaurant(): Promise<{ user: User; role: Role }> {
  return requireRole(VERIFICATION_MODERATOR_ROLES);
}

// --- Trip ownership/collaboration primitives ---------------------------
//
// Ports the live `is_trip_owner` SECURITY DEFINER function (MIGRATION_PLAN.md
// §3a) plus a new collaborator-lookup primitive. Prisma bypasses RLS, so
// `lib/server/trips.ts`'s `requireTripAccess()` (Step 4) composes these two
// rather than re-querying `trips`/`trip_collaborators` itself — this module
// stays the single place that decides "is this user allowed to see this
// trip," per the architecture decision in MIGRATION_PLAN.md §0.

/** Mirrors the live `is_trip_owner(trip_id, user_id)` function. */
export async function isTripOwner(userId: string, tripId: string): Promise<boolean> {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: { ownerId: true },
  });
  return trip?.ownerId === userId;
}

/**
 * A collaborator only counts as having access once their invite is
 * `"confirmed"` — a `"pending"` (or any other non-confirmed) status mirrors
 * an invite that hasn't been accepted yet and must not grant read access.
 */
export async function isTripCollaborator(userId: string, tripId: string): Promise<boolean> {
  const collaborator = await prisma.tripCollaborator.findUnique({
    where: { tripId_userId: { tripId, userId } },
    select: { status: true },
  });
  return collaborator?.status === "confirmed";
}

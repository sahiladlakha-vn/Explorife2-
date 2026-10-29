import "server-only";
import { cache } from "react";
import { notFound } from "next/navigation";
import { prisma } from "@/lib/db";
import { requireUser } from "@/lib/auth/permissions";
import type { Trip } from "@/lib/generated/prisma/client";

/**
 * Step 4 trip-read surface (MIGRATION_PLAN.md §7 Step 4 / §3a). Prisma
 * bypasses RLS, so EVERY read in this module is scoped in code to the
 * owner or a confirmed collaborator — there is no DB-side safety net here.
 * Unauthorized access to a real tripId returns a 404 (`notFound()`), never a
 * 403, so a guessed/enumerated tripId can't be distinguished from one that
 * simply doesn't exist.
 *
 * `requireTripAccess`/`listTripsForUser` are wrapped in React's `cache()` so
 * that the trip layout and its leaf page (which both call into this module
 * for the same request) share one underlying query instead of issuing it
 * twice — `cache()` memoizes per request, not across requests, so this is
 * purely a within-request dedupe, not a correctness-affecting cache. Both
 * the layout and the page still call `requireTripAccess` themselves (rather
 * than the page trusting the layout already checked) so the access check
 * can never be bypassed by rendering a leaf page in isolation.
 */

export interface TripAccess {
  user: Awaited<ReturnType<typeof requireUser>>;
  trip: Trip;
}

/**
 * Throws/redirects via Next's `requireUser()` (no session) or calls
 * `notFound()` (trip doesn't exist, or exists but the current user is
 * neither the owner nor a `"confirmed"` collaborator — a `"pending"` invite
 * does not grant access). Call this first in every trip layout/page.
 */
export const requireTripAccess = cache(async function requireTripAccess(
  tripId: string,
): Promise<TripAccess> {
  const user = await requireUser();

  const trip = await prisma.trip.findUnique({ where: { id: tripId } });
  if (!trip) {
    notFound();
  }

  const isOwner = trip.ownerId === user.id;
  if (!isOwner) {
    const collaborator = await prisma.tripCollaborator.findUnique({
      where: { tripId_userId: { tripId, userId: user.id } },
      select: { status: true },
    });
    if (collaborator?.status !== "confirmed") {
      notFound();
    }
  }

  return { user, trip };
});

/** Convenience wrapper — same guard as `requireTripAccess`, named for call sites that only want the trip. */
export async function getTripForUser(tripId: string): Promise<Trip> {
  const { trip } = await requireTripAccess(tripId);
  return trip;
}

/** All trips the user owns or is a confirmed collaborator on, earliest start date first. */
export const listTripsForUser = cache(async function listTripsForUser(
  userId: string,
): Promise<Trip[]> {
  return prisma.trip.findMany({
    where: {
      OR: [{ ownerId: userId }, { collaborators: { some: { userId, status: "confirmed" } } }],
    },
    orderBy: { startDate: "asc" },
  });
});

function todayUtcMidnight(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

/**
 * Resolves the user's "active" trip for `/profile/trips` and the old
 * `?tab=1` redirect: an ongoing trip (today within start–end, inclusive)
 * first; otherwise the nearest upcoming trip; otherwise the most recently
 * ended past trip; `null` if the user has no trips at all (the caller shows
 * an empty state with a "Plan a trip" CTA rather than redirecting).
 */
export async function getActiveTripId(userId: string): Promise<string | null> {
  const trips = await listTripsForUser(userId);
  if (trips.length === 0) return null;

  const today = todayUtcMidnight();

  const ongoing = trips.find((trip) => trip.startDate <= today && trip.endDate >= today);
  if (ongoing) return ongoing.id;

  const upcoming = trips
    .filter((trip) => trip.startDate > today)
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime())[0];
  if (upcoming) return upcoming.id;

  const past = trips
    .filter((trip) => trip.endDate < today)
    .sort((a, b) => b.endDate.getTime() - a.endDate.getTime())[0];
  return past?.id ?? null;
}

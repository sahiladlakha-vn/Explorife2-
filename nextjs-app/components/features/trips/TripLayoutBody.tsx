import type { ReactNode } from "react";
import Link from "next/link";
import { getOptionalUser } from "@/lib/auth/permissions";
import { requireTripAccess, listTripsForUser } from "@/lib/server/trips";
import { TripHeader } from "./TripHeader";

/**
 * Isolates the dynamic data access (`params`, and `cookies()` via
 * `requireTripAccess`) behind its own Server Component so
 * `[tripId]/layout.tsx` can stay a static shell and wrap just this piece in
 * `<Suspense>`.
 *
 * Checks `getOptionalUser()` first (Step 5) so a zero-session visit (incl.
 * `<Link>` prefetch) renders a guest view instead of throwing — same
 * reasoning as `ProfileLayoutBody`. Once a session (guest or real) exists,
 * `requireTripAccess` still runs its own full ownership/collaborator check
 * itself rather than trusting this pre-check, same as every leaf page under
 * `[tripId]/` already does.
 */
export async function TripLayoutBody({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tripId: string }>;
}) {
  const sessionUser = await getOptionalUser();

  if (!sessionUser) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 py-16 text-center">
        <p className="text-text text-lg font-medium">Sign in to view this trip</p>
        <Link
          href="/auth?redirect=%2Fprofile%2Ftrips"
          className="bg-accent mt-2 rounded-full px-5 py-2 text-sm font-medium text-white"
        >
          Sign in
        </Link>
      </div>
    );
  }

  const { tripId } = await params;
  const { user, trip } = await requireTripAccess(tripId);
  const trips = await listTripsForUser(user.id);

  return (
    <>
      <TripHeader trips={trips} activeTrip={trip} />
      <div className="flex flex-1 flex-col">{children}</div>
    </>
  );
}

import type { ReactNode } from "react";
import { requireTripAccess, listTripsForUser } from "@/lib/server/trips";
import { TripHeader } from "./TripHeader";

/**
 * Isolates the dynamic data access (`params`, and `cookies()` via
 * `requireTripAccess`) behind its own Server Component so
 * `[tripId]/layout.tsx` can stay a static shell and wrap just this piece in
 * `<Suspense>`.
 */
export async function TripLayoutBody({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tripId: string }>;
}) {
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

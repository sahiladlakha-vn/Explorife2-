import { requireTripAccess } from "@/lib/server/trips";

/**
 * `instant = false` — see `app/profile/trips/[tripId]/page.tsx`'s comment:
 * `TripLayoutBody`'s own independent auth gate withholds `{children}` (this
 * page) when there's no session, distinct from `ProfileLayoutBody`'s outer
 * gate already handled on `[tripId]/layout.tsx`.
 */
export const instant = false;

export default async function BookingsPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  await requireTripAccess(tripId);

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 py-16 text-center">
      <p className="text-text-muted text-sm">No bookings yet.</p>
    </div>
  );
}

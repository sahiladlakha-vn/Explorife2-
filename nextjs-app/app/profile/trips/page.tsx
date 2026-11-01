import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/permissions";
import { getActiveTripId } from "@/lib/server/trips";

/**
 * `/profile/trips` (and old `?tab=1` with no `tripId`) resolves to the
 * user's active trip (ongoing, else nearest upcoming, else most recent
 * past — see `getActiveTripId`). A user with zero trips sees an empty state
 * here instead of being redirected anywhere.
 */
/**
 * `instant = false` — see `app/profile/overview/page.tsx`'s comment:
 * `ProfileLayoutBody` withholds `{children}` (this page) when there's no
 * session/profile, which is the documented "slot gated by authentication"
 * case for this fix rather than rendering the dropped segment.
 */
export const instant = false;

export default async function TripsIndexPage() {
  const user = await requireUser();
  const activeTripId = await getActiveTripId(user.id);

  if (activeTripId) {
    redirect(`/profile/trips/${activeTripId}/trip`);
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <p className="text-text text-lg font-medium">No trips yet</p>
      <p className="text-text-muted max-w-sm text-sm">
        Plan your first trip to see it here — your itinerary, budget and bookings all live
        together once you do.
      </p>
      <button
        type="button"
        disabled
        aria-label="Plan a trip — coming soon"
        title="Coming soon"
        className="bg-accent mt-2 cursor-not-allowed rounded-full px-5 py-2 text-sm font-medium text-white opacity-50"
      >
        Plan a trip
      </button>
    </div>
  );
}

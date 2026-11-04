import { getTripStops, requireTripAccess } from "@/lib/server/trips";
import { buildItinerary } from "@/lib/trips/itinerary";
import { ItineraryView } from "@/components/features/trips/ItineraryView";

/**
 * `instant = false` — see `app/profile/trips/[tripId]/page.tsx`'s comment:
 * `TripLayoutBody`'s own independent auth gate withholds `{children}` (this
 * page) when there's no session, distinct from `ProfileLayoutBody`'s outer
 * gate already handled on `[tripId]/layout.tsx`.
 */
export const instant = false;

export default async function ItineraryPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  const { trip } = await requireTripAccess(tripId);
  const stops = await getTripStops(tripId);
  const days = buildItinerary(trip, stops);

  return (
    <div className="flex flex-1 flex-col gap-4 px-4 py-6 md:px-6 lg:px-8">
      <ItineraryView days={days} currency={trip.currency} />
    </div>
  );
}

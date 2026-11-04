import { requireTripAccess } from "@/lib/server/trips";
import { formatTripDateRange } from "@/lib/format/trip-dates";

/**
 * `instant = false` — see `app/profile/trips/[tripId]/page.tsx`'s comment:
 * `TripLayoutBody`'s own independent auth gate withholds `{children}` (this
 * page) when there's no session, distinct from `ProfileLayoutBody`'s outer
 * gate already handled on `[tripId]/layout.tsx`.
 */
export const instant = false;

export default async function TripOverviewPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  const { trip } = await requireTripAccess(tripId);

  return (
    <div className="flex flex-1 flex-col gap-4 px-4 py-6 md:px-6 lg:px-8">
      <div>
        <h1 className="text-text text-xl font-semibold">{trip.name}</h1>
        <p className="text-text-muted text-sm">{trip.location}</p>
        <p className="text-text-muted text-sm">
          {formatTripDateRange(trip.startDate, trip.endDate)}
        </p>
      </div>
      {trip.description && <p className="text-text text-sm">{trip.description}</p>}
    </div>
  );
}

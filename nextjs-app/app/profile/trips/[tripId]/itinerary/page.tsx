import { requireTripAccess } from "@/lib/server/trips";
import { ItineraryMapLoader } from "@/components/features/trips/ItineraryMapLoader";

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
  await requireTripAccess(tripId);

  return (
    <div className="flex flex-1 flex-col gap-4 px-4 py-6 md:px-6 lg:px-8">
      <ItineraryMapLoader />
    </div>
  );
}

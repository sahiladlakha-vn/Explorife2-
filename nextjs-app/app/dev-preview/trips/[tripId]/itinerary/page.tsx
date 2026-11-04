import { notFound } from "next/navigation";
import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { getDevPreviewItineraryStops, getDevPreviewTrip } from "@/lib/dev-preview/fixtures";
import { buildItinerary } from "@/lib/trips/itinerary";
import { ItineraryView } from "@/components/features/trips/ItineraryView";

export default async function DevPreviewItineraryTabPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  assertDevPreviewEnabled();

  const { tripId } = await params;
  const trip = getDevPreviewTrip(tripId);
  if (!trip) notFound();

  const stops = getDevPreviewItineraryStops(tripId);
  const days = buildItinerary(trip, stops);

  return (
    <div className="px-4 py-6 md:px-6 lg:px-8">
      <ItineraryView days={days} currency={trip.currency} />
    </div>
  );
}

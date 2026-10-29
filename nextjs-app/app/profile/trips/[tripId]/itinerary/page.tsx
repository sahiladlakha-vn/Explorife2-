import { requireTripAccess } from "@/lib/server/trips";
import { ItineraryMapLoader } from "@/components/features/trips/ItineraryMapLoader";

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

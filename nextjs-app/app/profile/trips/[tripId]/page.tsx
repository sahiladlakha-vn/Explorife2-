import { redirect } from "next/navigation";

/** `/profile/trips/[tripId]` with no sub-tab segment lands on the trip overview. */
export default async function TripIndexPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  redirect(`/profile/trips/${tripId}/trip`);
}

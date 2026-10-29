import { requireTripAccess } from "@/lib/server/trips";

const VND_FORMAT = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });

export default async function DashboardPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  const { trip } = await requireTripAccess(tripId);

  const budget = `${VND_FORMAT.format(Number(trip.budgetVnd))} ${trip.currency}`;

  return (
    <div className="grid flex-1 grid-cols-2 gap-3 px-4 py-6 md:grid-cols-4 md:px-6 lg:px-8">
      <div className="bg-surface-raised rounded-lg p-4">
        <p className="text-text-muted text-xs font-medium uppercase">Budget</p>
        <p className="text-text mt-1 text-lg font-semibold">{budget}</p>
      </div>
      <div className="bg-surface-raised rounded-lg p-4">
        <p className="text-text-muted text-xs font-medium uppercase">Spent</p>
        <p className="text-text mt-1 text-lg font-semibold">—</p>
      </div>
      <div className="bg-surface-raised rounded-lg p-4">
        <p className="text-text-muted text-xs font-medium uppercase">Remaining</p>
        <p className="text-text mt-1 text-lg font-semibold">—</p>
      </div>
      <div className="bg-surface-raised rounded-lg p-4">
        <p className="text-text-muted text-xs font-medium uppercase">Per Person</p>
        <p className="text-text mt-1 text-lg font-semibold">—</p>
      </div>
    </div>
  );
}

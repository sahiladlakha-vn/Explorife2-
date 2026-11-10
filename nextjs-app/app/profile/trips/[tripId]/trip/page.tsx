import { requireTripAccess } from "@/lib/server/trips";
import { getTripSetup } from "@/lib/server/trip-setup";
import { TravelersCard } from "@/components/features/trips/TravelersCard";
import { DocumentsCard } from "@/components/features/trips/DocumentsCard";
import { PackingCard } from "@/components/features/trips/PackingCard";

/**
 * `instant = false` — see `app/profile/trips/[tripId]/page.tsx`'s comment:
 * `TripLayoutBody`'s own independent auth gate withholds `{children}` (this
 * page) when there's no session, distinct from `ProfileLayoutBody`'s outer
 * gate already handled on `[tripId]/layout.tsx`.
 */
export const instant = false;

/**
 * Ports `_TripSegment` (trips_tab.dart:589-680) — the shared `header`
 * (switcher/sub-tabs) is already rendered one level up by `TripHeader`
 * (`TripLayoutBody`), so this leaf page is just the three-card body.
 *
 * Left column: Travelers + Documents stacked (both reference/roster lists).
 * Right column: Packing — its own progress bar already gives it distinct
 * visual weight, so it reads fine as the sole right-column card. Below
 * `lg:` (1024px, Tailwind's default breakpoint and also Dart's
 * `Breakpoints.desktopWide` threshold) this collapses to a single column,
 * same order as the Dart source (Travelers -> Documents -> Packing). The
 * 16px gap between stacked sections mirrors the Dart `SizedBox(height: 16)`
 * used both between Travelers/Documents within `left` and between `left`/
 * `right` in the narrow-width `Column` fallback; the row gap widens to 20px
 * at `lg:` to mirror `AppSpacing.sectionGap`, the width Dart uses between
 * `left`/`right` in the two-column `Row`. `TravelersCard`/`DocumentsCard`/
 * `PackingCard` each fold in their own `_CardHeader` (see their own doc
 * comments), so none is repeated here.
 */
export default async function TripOverviewPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  const { user, trip } = await requireTripAccess(tripId);
  const { travelers, documents, packingItems } = await getTripSetup(tripId);

  return (
    <div className="flex flex-1 flex-col px-4 py-6 md:px-6 lg:px-8">
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2 lg:items-start lg:gap-5">
        <div className="flex flex-col gap-4">
          <TravelersCard tripId={trip.id} travelers={travelers} currentUserId={user.id} />
          <DocumentsCard trip={trip} documents={documents} travelers={travelers} />
        </div>
        <div className="flex flex-col gap-4">
          <PackingCard tripId={trip.id} items={packingItems} travelers={travelers} />
        </div>
      </div>
    </div>
  );
}

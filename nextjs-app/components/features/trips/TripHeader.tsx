import { Suspense } from "react";
import type { Trip } from "@/lib/generated/prisma/client";
import { TripSwitcher } from "./TripSwitcher";
import { TripSubTabs } from "./TripSubTabs";
import { TripSubTabsSkeleton } from "./TripHeaderSkeleton";
import { CalendarIconButton } from "./CalendarIconButton";
import { NewTripButton } from "./NewTripButton";

interface TripHeaderProps {
  trips: Trip[];
  activeTrip: Trip;
}

/**
 * All three children are flat siblings of one flex-wrap container — no
 * `display: contents` wrapper — so `order` alone reshuffles them at each
 * breakpoint. <768px: the sub-tabs are `basis-full`, which forces a wrap
 * onto their own row below the title block + actions. >=768px: `flex-1` on
 * the sub-tabs (no longer full-width) lets them sit inline between the
 * switcher and actions, consuming the remaining row width.
 *
 * `TripSubTabs` gets its own `<Suspense>` boundary (not just the shared one
 * around `TripLayoutBody`/`DevPreviewTripLayout`) because it calls
 * `useSelectedLayoutSegment()`, which Next 16's instant-navigation
 * validation flags as URL data read outside Suspense on this dynamic-param
 * route (docs: https://nextjs.org/docs/messages/blocking-prerender-client-hook).
 * Scoping the boundary to just the sub-tabs — rather than wrapping all of
 * `TripHeader` — keeps the switcher trigger and action buttons in the
 * static shell; only the active-tab pill styling streams in.
 */
export function TripHeader({ trips, activeTrip }: TripHeaderProps) {
  return (
    <div
      data-testid="trip-header"
      className="border-border bg-surface flex flex-wrap items-center gap-2 border-b px-4 py-3 md:flex-nowrap md:gap-4"
    >
      <TripSwitcher trips={trips} activeTrip={activeTrip} />
      <div className="flex shrink-0 items-center gap-1 md:order-3">
        <CalendarIconButton />
        <NewTripButton />
      </div>
      <div className="-mx-4 w-full basis-full overflow-x-auto px-4 md:order-2 md:mx-0 md:w-auto md:flex-1 md:basis-auto md:px-0">
        <Suspense fallback={<TripSubTabsSkeleton />}>
          <TripSubTabs tripId={activeTrip.id} />
        </Suspense>
      </div>
    </div>
  );
}

/**
 * Mirrors `TripSubTabs`'s exact box structure — four pill buttons, same
 * height/shape — so its own `<Suspense>` fallback (now wrapping just the
 * sub-tabs inside `TripHeader`, not the whole header) reserves identical
 * space. `TripSubTabs` calls `useSelectedLayoutSegment()`, which Next 16's
 * instant-navigation validation flags as "URL data in a Client Component
 * outside of Suspense" on this dynamic-param (`[tripId]`) route — see
 * https://nextjs.org/docs/messages/blocking-prerender-client-hook. Wrapping
 * just this nav (not the rest of `TripHeader`) keeps the switcher trigger
 * and action buttons in the static shell per the docs' "push the hook read
 * down to the leaf" guidance.
 */
export function TripSubTabsSkeleton() {
  return (
    <nav aria-hidden className="flex animate-pulse shrink-0 gap-1">
      {["Trip", "Itinerary", "Dashboard", "Bookings"].map((label) => (
        <div
          key={label}
          className="bg-surface-raised h-7 w-20 shrink-0 rounded-full px-3 py-1.5 text-sm font-medium"
        >
          &nbsp;
        </div>
      ))}
    </nav>
  );
}

/**
 * Mirrors `TripHeader`'s exact container/child classes (same flex-wrap,
 * order, basis, and padding utilities) so the Suspense fallback reserves
 * identical height at every breakpoint — including the <768px wrap onto a
 * second row — with no layout shift once the real header streams in.
 */
export function TripHeaderSkeleton() {
  return (
    <div
      aria-hidden
      className="border-border bg-surface flex animate-pulse flex-wrap items-center gap-2 border-b px-4 py-3 md:flex-nowrap md:gap-4"
    >
      <div className="flex min-w-0 items-center gap-1.5 rounded-md px-2 py-1">
        <div className="min-w-0">
          <div className="bg-surface-raised h-5 w-32 rounded text-base font-semibold">&nbsp;</div>
          <div className="bg-surface-raised mt-1 h-3.5 w-24 rounded text-xs">&nbsp;</div>
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1 md:order-3">
        <div className="bg-surface-raised h-9 w-9 shrink-0 rounded-full" />
        <div className="bg-surface-raised h-9 w-9 shrink-0 rounded-full md:w-24" />
      </div>
      <div className="-mx-4 w-full basis-full overflow-x-auto px-4 md:order-2 md:mx-0 md:w-auto md:flex-1 md:basis-auto md:px-0">
        <TripSubTabsSkeleton />
      </div>
    </div>
  );
}

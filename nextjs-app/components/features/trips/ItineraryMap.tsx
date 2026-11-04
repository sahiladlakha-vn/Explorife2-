"use client";

/**
 * Placeholder pending the real Mapbox GL integration (MIGRATION_PLAN.md §7
 * Step 4 is read-only) — kept as its own client component so the page can
 * `dynamic(..., { ssr: false })` it without a map library needing to touch
 * the server bundle.
 */
export function ItineraryMap() {
  const hasToken = Boolean(process.env.NEXT_PUBLIC_MAPBOX_TOKEN);

  return (
    <div className="bg-surface-raised text-text-muted flex h-64 w-full items-center justify-center rounded-lg text-sm md:h-96">
      {hasToken ? "Map coming soon" : "Map unavailable — missing NEXT_PUBLIC_MAPBOX_TOKEN"}
    </div>
  );
}

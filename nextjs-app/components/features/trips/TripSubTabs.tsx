"use client";

import Link from "next/link";
import { useSelectedLayoutSegment } from "next/navigation";
import { cn } from "@/lib/utils";

const SUB_TABS = [
  { segment: "trip", label: "Trip" },
  { segment: "itinerary", label: "Itinerary" },
  { segment: "dashboard", label: "Dashboard" },
  { segment: "bookings", label: "Bookings" },
] as const;

/**
 * Client component so `useSelectedLayoutSegment()` can track the active
 * sub-tab — `[tripId]/layout.tsx` renders once and doesn't re-render on
 * sibling navigation (trip -> itinerary -> dashboard -> bookings), so a prop
 * computed in the layout would go stale the moment the user switches tabs.
 */
export function TripSubTabs({ tripId }: { tripId: string }) {
  const segment = useSelectedLayoutSegment();

  return (
    <nav className="flex shrink-0 gap-1">
      {SUB_TABS.map((tab) => {
        const isActive = segment === tab.segment;
        return (
          <Link
            key={tab.segment}
            href={`/profile/trips/${tripId}/${tab.segment}`}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "shrink-0 rounded-full px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors",
              isActive ? "bg-accent text-white" : "text-text-muted hover:text-text",
            )}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}

"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { useSelectedLayoutSegment } from "next/navigation";
import type { Trip } from "@/lib/generated/prisma/client";
import { formatTripDateRange } from "@/lib/format/trip-dates";
import { cn } from "@/lib/utils";

const VND_FORMAT = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });

function budgetLabel(trip: Trip): string {
  return `${VND_FORMAT.format(Number(trip.budgetVnd))} ${trip.currency}`;
}

interface TripListProps {
  trips: Trip[];
  activeTripId: string;
  onNavigate?: () => void;
}

/**
 * Shared between the ≥768px popover and <768px bottom sheet (see
 * TripSwitcher). Groups by Upcoming (today's ongoing trip counts as
 * upcoming — it hasn't ended) / Past, scrolls the active trip into view on
 * mount, and supports arrow-key roving between items (Radix Popover/Dialog
 * already handle Esc-to-close-and-restore-focus and outside-click/Tab
 * trapping; this component only owns up/down navigation between trips).
 *
 * Reads `useSelectedLayoutSegment()` itself (rather than taking it as a
 * `segment` prop from `TripSwitcher`) so the sub-tab to land on for the
 * selected trip can stay behind its own `<Suspense>` boundary, scoped to
 * just this list — see `TripSwitcher`'s doc comment for why.
 */
export function TripList({ trips, activeTripId, onNavigate }: TripListProps) {
  const segment = useSelectedLayoutSegment() ?? "trip";
  const activeRef = useRef<HTMLAnchorElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    activeRef.current?.scrollIntoView({ block: "nearest" });
  }, []);

  const today = new Date(
    Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate()),
  );
  const upcoming = trips
    .filter((t) => t.endDate >= today)
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime());
  const past = trips
    .filter((t) => t.endDate < today)
    .sort((a, b) => b.endDate.getTime() - a.endDate.getTime());

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    const items = Array.from(
      listRef.current?.querySelectorAll<HTMLAnchorElement>("a[data-trip-item]") ?? [],
    );
    if (items.length === 0) return;
    const currentIndex = items.indexOf(document.activeElement as HTMLAnchorElement);
    const delta = event.key === "ArrowDown" ? 1 : -1;
    const nextIndex = currentIndex === -1 ? 0 : (currentIndex + delta + items.length) % items.length;
    items[nextIndex]?.focus();
  }

  function renderGroup(label: string, group: Trip[]) {
    if (group.length === 0) return null;
    return (
      <div key={label}>
        <p className="text-text-muted px-3 pt-3 pb-1 text-xs font-semibold tracking-wide uppercase">
          {label}
        </p>
        {group.map((trip) => {
          const isActive = trip.id === activeTripId;
          return (
            <Link
              key={trip.id}
              ref={isActive ? activeRef : undefined}
              data-trip-item
              href={`/profile/trips/${trip.id}/${segment}`}
              onClick={onNavigate}
              className={cn(
                "flex items-center justify-between gap-2 rounded-md px-3 py-2 text-sm transition-colors",
                "hover:bg-surface-raised focus-visible:bg-surface-raised focus-visible:outline-none",
                isActive && "bg-surface-raised",
              )}
            >
              <span className="min-w-0 flex-1">
                <span className="text-text block truncate font-medium">{trip.name}</span>
                <span className="text-text-muted block truncate text-xs">
                  {formatTripDateRange(trip.startDate, trip.endDate)}
                </span>
              </span>
              <span className="text-text-muted shrink-0 text-xs">{budgetLabel(trip)}</span>
              {isActive && <CheckBadge />}
            </Link>
          );
        })}
      </div>
    );
  }

  return (
    <div
      ref={listRef}
      role="listbox"
      aria-label="Your trips"
      onKeyDown={handleKeyDown}
      className="max-h-[420px] w-full overflow-y-auto py-1"
    >
      {renderGroup("Upcoming", upcoming)}
      {renderGroup("Past", past)}
    </div>
  );
}

function CheckBadge() {
  return (
    <span className="bg-accent flex h-4 w-4 shrink-0 items-center justify-center rounded-full text-white">
      <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className="h-3 w-3">
        <path
          d="M4 10.5L8 14.5L16 6"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

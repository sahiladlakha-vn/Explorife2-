"use client";

import { cn } from "@/lib/utils";
import { formatDayChip } from "@/lib/format/trip-dates";
import type { DayItinerary } from "@/lib/trips/itinerary";

interface DayStripProps {
  days: DayItinerary[];
  activeDay: number;
  onSelect: (day: number) => void;
}

/**
 * Horizontal day-chip rail, ported from `trips_tab.dart`'s `_DayRail`/
 * `_DayRailChip` — the active chip's white-fill/black-text treatment (not an
 * accent-orange fill) is intentional, matching the Flutter source exactly.
 * No trailing "+" add-day chip here since Step 4 is read-only
 * (MIGRATION_PLAN.md §7).
 */
export function DayStrip({ days, activeDay, onSelect }: DayStripProps) {
  return (
    <div
      data-testid="itinerary-day-strip"
      role="tablist"
      aria-label="Trip days"
      className="flex gap-2 overflow-x-auto pb-1"
    >
      {days.map((d) => {
        const { weekday, dayOfMonth } = formatDayChip(d.date);
        const isActive = d.day === activeDay;
        return (
          <button
            key={d.day}
            type="button"
            role="tab"
            aria-selected={isActive}
            data-testid={`day-chip-${d.day}`}
            onClick={() => onSelect(d.day)}
            className={cn(
              "flex w-13 shrink-0 flex-col items-center gap-0.5 rounded-xl border py-1.5 transition-colors",
              isActive ? "border-white bg-white" : "border-border bg-surface-raised",
            )}
          >
            <span
              className={cn(
                "text-[9px] font-bold tracking-wide",
                isActive ? "text-black/60" : "text-text-muted",
              )}
            >
              {weekday}
            </span>
            <span className={cn("text-xl leading-none", isActive ? "text-black" : "text-text")}>
              {dayOfMonth}
            </span>
          </button>
        );
      })}
    </div>
  );
}

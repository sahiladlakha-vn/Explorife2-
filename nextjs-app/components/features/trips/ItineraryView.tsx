"use client";

import { useState } from "react";
import { useMediaQuery } from "@/lib/hooks/use-media-query";
import { SLOT_ORDER, type DayItinerary } from "@/lib/trips/itinerary";
import { formatDayHeading } from "@/lib/format/trip-dates";
import { DayStrip } from "./DayStrip";
import { SlotSection } from "./SlotSection";
import { ItineraryMapLoader } from "./ItineraryMapLoader";

interface ItineraryViewProps {
  days: DayItinerary[];
  currency: string;
}

/**
 * Day rail + the active day's slot sections, side-by-side with the day map
 * on >=768px and stacked below it on narrower screens — ported from
 * `trips_tab.dart`'s `_ItinerarySegmentState`. Flutter's own split breakpoint
 * is a 760px *container* width via `LayoutBuilder`; this uses a 768px
 * viewport media query (Tailwind's `md`) instead since nothing here competes
 * with the viewport for width. `activeDay` starts at 1, same as the Flutter
 * source — no "jump to today" logic for which DAY is shown (that only
 * applies to which TRIP is active, see `getActiveTripId`).
 */
export function ItineraryView({ days, currency }: ItineraryViewProps) {
  const [activeDay, setActiveDay] = useState(1);
  const isDesktop = useMediaQuery("(min-width: 768px)");

  const safeDay = Math.min(Math.max(activeDay, 1), days.length);
  const day = days[safeDay - 1];

  const dayPanel = (
    <div data-testid="itinerary-day-panel" className="border-border bg-surface rounded-2xl border p-3">
      <h2 className="text-text pb-2 text-lg">{formatDayHeading(day.day, day.date)}</h2>
      {SLOT_ORDER.map((slot) => (
        <SlotSection key={slot} slot={slot} stops={day.slots[slot]} currency={currency} />
      ))}
    </div>
  );

  const mapPanel = <ItineraryMapLoader stops={day.plottedStops} color={day.color} />;

  return (
    <div className="flex flex-col gap-3">
      <DayStrip days={days} activeDay={safeDay} onSelect={setActiveDay} />
      {isDesktop ? (
        <div className="flex flex-row items-start gap-3">
          <div className="w-[460px] shrink-0">{dayPanel}</div>
          <div className="flex-1">{mapPanel}</div>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {dayPanel}
          {mapPanel}
        </div>
      )}
    </div>
  );
}

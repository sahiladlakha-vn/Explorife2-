import { SLOT_EMOJI, SLOT_LABEL, transitEmoji } from "@/lib/trips/itinerary";
import type { ItineraryStopView, Slot, TransitView } from "@/lib/trips/itinerary";
import { formatCompactMoney } from "@/lib/format/money";
import { StopRow } from "./StopRow";

interface SlotSectionProps {
  slot: Slot;
  stops: ItineraryStopView[];
  currency: string;
}

/**
 * One slot's stops within a day: header + rows, ported from `trips_tab.dart`'s
 * `_SlotSection` — always rendered even when empty, so a day's three-part
 * shape (morning/afternoon/evening) reads at a glance. Read-only: no
 * "+ Add"/drag-reorder affordances (Step 4 is read-only, MIGRATION_PLAN.md §7).
 */
export function SlotSection({ slot, stops, currency }: SlotSectionProps) {
  return (
    <div data-testid={`slot-section-${slot}`} className="pb-2.5">
      <div className="mb-1.5 flex items-center gap-1.5">
        <span aria-hidden="true" className="text-xs">
          {SLOT_EMOJI[slot]}
        </span>
        <span className="text-text-muted text-xs font-semibold">{SLOT_LABEL[slot]}</span>
      </div>
      {stops.length === 0 ? (
        <p className="text-text-muted/70 pb-1 text-[11px] font-medium">Nothing planned yet</p>
      ) : (
        <div className="flex flex-col gap-2">
          {stops.map((stop) => (
            <div key={stop.id}>
              {stop.transit && <TransitThread transit={stop.transit} currency={currency} />}
              <StopRow stop={stop} currency={currency} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function TransitThread({ transit, currency }: { transit: TransitView; currency: string }) {
  const parts = [transit.mode];
  if (transit.line) parts.push(transit.line);
  if (transit.durationMin != null) parts.push(`${transit.durationMin} min`);
  if (transit.costVnd != null) parts.push(formatCompactMoney(transit.costVnd, currency));

  return (
    <div className="text-text-muted flex items-center gap-2 pt-0.5 pb-1.5 pl-[18px] text-[10.5px]">
      <span aria-hidden="true" className="text-xs">
        {transitEmoji(transit.mode)}
      </span>
      <span>{parts.join(" · ")}</span>
    </div>
  );
}

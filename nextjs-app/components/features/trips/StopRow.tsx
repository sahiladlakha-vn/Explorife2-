import { cn } from "@/lib/utils";
import { formatCompactMoney } from "@/lib/format/money";
import type { ItineraryStopView } from "@/lib/trips/itinerary";

interface StopRowProps {
  stop: ItineraryStopView;
  currency: string;
}

/**
 * One placed stop: thumbnail, time, name, a `category · duration · cost`
 * meta line, Cost-TBD/Booked chips, and notes — ported from `trips_tab.dart`'s
 * `_SpotRow`. Read-only: no drag handle, edit, or remove affordances (Step 4
 * is read-only, MIGRATION_PLAN.md §7).
 */
export function StopRow({ stop, currency }: StopRowProps) {
  const metaParts = [stop.category];
  if (stop.durationMin != null) metaParts.push(`${stop.durationMin}m`);
  if (stop.cost === 0) metaParts.push("Free");
  else if (stop.cost != null) metaParts.push(formatCompactMoney(stop.cost, currency));

  const showChips = stop.cost == null || stop.isBooked;

  return (
    <div
      data-testid="itinerary-stop-row"
      className="border-border bg-surface-raised flex items-start gap-2.5 rounded-2xl border p-3"
    >
      <StopThumb stop={stop} />
      <div className="min-w-0 flex-1">
        <p className="text-text-muted text-[11px] font-bold">{stop.timeLabel}</p>
        <p className="text-text mt-0.5 truncate text-sm font-bold">{stop.title}</p>
        <p className="text-text-muted mt-0.5 truncate text-[10.5px] tracking-wide">
          {metaParts.join(" · ")}
        </p>
        {showChips && (
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            {stop.cost == null && <StatusChip label="COST TBD" tone="warn" />}
            {stop.isBooked && <StatusChip label="BOOKED" tone="success" />}
          </div>
        )}
        {stop.notes && (
          <p className="text-text-muted mt-1 line-clamp-2 text-[11px] leading-snug">{stop.notes}</p>
        )}
      </div>
    </div>
  );
}

function StopThumb({ stop }: { stop: ItineraryStopView }) {
  return (
    <div className="bg-bg flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-[10px]">
      {stop.thumbKind === "photo" && stop.photoUrl ? (
        // eslint-disable-next-line @next/next/no-img-element -- gem photo hosts aren't configured for next/image yet
        <img src={stop.photoUrl} alt={stop.title} className="h-full w-full object-cover" />
      ) : stop.thumbKind === "emoji" && stop.emoji ? (
        <span aria-hidden="true" className="text-lg">
          {stop.emoji}
        </span>
      ) : stop.thumbKind === "custom" ? (
        <span aria-hidden="true" className="text-text-muted text-lg">
          ✎
        </span>
      ) : (
        <span aria-hidden="true" className="text-text-muted text-lg font-bold">
          ?
        </span>
      )}
    </div>
  );
}

function StatusChip({ label, tone }: { label: string; tone: "warn" | "success" }) {
  return (
    <span
      className={cn(
        "rounded-full px-2 py-0.5 text-[9.5px] font-bold tracking-wide",
        tone === "warn" ? "bg-warn/15 text-warn" : "bg-success/15 text-success",
      )}
    >
      {label}
    </span>
  );
}

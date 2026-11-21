import type { CSSProperties } from "react";
import type { DayString, WeekTrip } from "@/lib/dashboard/types";
import { buildWeekDays, layoutWeekSpans } from "@/lib/dashboard/week-strip";
import { cn } from "@/lib/utils";

const MAX_LANES = 4;

/**
 * Seven-day strip (Monday first, today highlighted) with each trip drawn as a
 * bar from its start day to its end day, clipped to the week. Overlapping
 * trips stack in lanes; more than {MAX_LANES} lanes collapse into "+N more".
 * Purely a function of `weekStart`/`today`/`trips` — it never reads the clock.
 */
export function WeekStrip({
  weekStart,
  today,
  trips,
}: {
  weekStart: DayString;
  today: DayString;
  trips: WeekTrip[];
}) {
  const days = buildWeekDays(weekStart, today);
  const { spans } = layoutWeekSpans(trips, weekStart);
  const visible = spans.filter((span) => span.lane < MAX_LANES);
  const hidden = spans.length - visible.length;

  return (
    <div data-testid="week-strip">
      <div className="grid grid-cols-7 gap-1 text-center">
        {days.map((day) => (
          <div
            key={day.date}
            data-today={day.isToday ? "true" : undefined}
            className={cn(
              "rounded-xl py-1.5",
              day.isToday ? "bg-white text-neutral-900" : "bg-white/10 text-white/90",
            )}
          >
            <p className="text-[11px] font-medium uppercase">{day.weekday}</p>
            <p className="text-sm font-semibold tabular-nums">{day.dayOfMonth}</p>
          </div>
        ))}
      </div>

      {visible.length > 0 && (
        <div className="mt-2 grid grid-cols-7 gap-x-1 gap-y-1.5" style={{ gridAutoRows: "1.75rem" }}>
          {visible.map((span) => (
            <div
              key={span.id}
              data-testid="week-trip"
              title={`${span.name} · ${span.location}`}
              style={{ gridColumn: `${span.startCol} / ${span.endCol + 1}`, gridRow: span.lane + 1 } as CSSProperties}
              className={cn(
                "bg-dash-accent flex items-center overflow-hidden px-2 text-xs font-semibold text-neutral-900",
                span.continuesBefore ? "rounded-l-sm" : "rounded-l-full",
                span.continuesAfter ? "rounded-r-sm" : "rounded-r-full",
              )}
            >
              <span className="truncate">{span.name}</span>
            </div>
          ))}
        </div>
      )}

      {hidden > 0 && <p className="mt-2 text-xs text-white/70">+{hidden} more this week</p>}
    </div>
  );
}

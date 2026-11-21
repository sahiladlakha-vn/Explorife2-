import { Wallet } from "lucide-react";
import { monthDayShort, weekdayShort } from "@/lib/dashboard/booking-trends";
import type { Section } from "@/lib/dashboard/section";
import type { BookingValueSummary } from "@/lib/dashboard/types";
import { formatCompactVnd } from "@/lib/format/vnd";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { ChangeBadge } from "./primitives/ChangeBadge";
import { ColumnBars } from "./primitives/ColumnBars";
import { GlassCard } from "./primitives/GlassCard";

/**
 * Paid booking value for the last 7 days by weekday, with a badge comparing
 * that total to the 7 days before. "Booking value" is what travelers logged as
 * paid on their trips — not revenue.
 */
export function BookingValueCard({
  section,
  index = 0,
}: {
  section: Section<BookingValueSummary>;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-booking-value">
      <CardHeader label="Booking Value (Paid)" icon={Wallet} />
      {section.status === "error" ? (
        <CardError label="Couldn't load booking value" />
      ) : (
        <BookingValueBody summary={section.data} />
      )}
    </GlassCard>
  );
}

function BookingValueBody({ summary }: { summary: BookingValueSummary }) {
  const week = summary.daily.slice(-7);
  const hasPaidThisWeek = week.some((day) => day.amountVnd > 0);

  return (
    <>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-4xl font-light tracking-tight tabular-nums">{formatCompactVnd(summary.last7Vnd)}</p>
          <p className="text-xs text-white/70">paid in the last 7 days</p>
        </div>
        <ChangeBadge percent={summary.changePercent} hasCurrent={summary.last7Vnd > 0} />
      </div>

      <div className="mt-5">
        {hasPaidThisWeek ? (
          <ColumnBars
            ariaLabel="Paid booking value by weekday, last 7 days"
            items={week.map((day) => ({
              key: day.day,
              label: weekdayShort(day.day),
              value: day.amountVnd,
              tooltip: `${weekdayShort(day.day)} ${monthDayShort(day.day)} · ${formatCompactVnd(day.amountVnd)}`,
            }))}
          />
        ) : (
          <CardEmpty
            message="No paid bookings in the last 7 days"
            hint="Bookings marked Paid will appear here by weekday."
          />
        )}
      </div>

      <p className="mt-4 text-xs text-white/70">
        {summary.paidCount} paid {summary.paidCount === 1 ? "booking" : "bookings"} ·{" "}
        {formatCompactVnd(summary.paidVnd)} all time
      </p>
    </>
  );
}

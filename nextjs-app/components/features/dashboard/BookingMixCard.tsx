"use client";

import { useState } from "react";
import { PieChart } from "lucide-react";
import { periodWindowPhrase, type PerformancePeriod } from "@/lib/dashboard/periods";
import type { Section } from "@/lib/dashboard/section";
import type { BookingMixEntry, ByPeriod } from "@/lib/dashboard/types";
import { formatCompactVnd } from "@/lib/format/vnd";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";
import { SegmentToggle } from "./primitives/SegmentToggle";

type Metric = "count" | "value";

/** Bookings created in the chosen window, per booking type, by count or by total amount. */
export function BookingMixCard({
  section,
  period,
  index = 0,
}: {
  section: Section<ByPeriod<BookingMixEntry[]>>;
  period: PerformancePeriod;
  index?: number;
}) {
  const [metric, setMetric] = useState<Metric>("count");

  return (
    <GlassCard index={index} testId="card-booking-mix">
      <CardHeader
        label="Booking Mix"
        icon={PieChart}
        trailing={
          section.status === "ok" ? (
            <SegmentToggle
              label="Booking mix metric"
              options={[
                { label: "Bookings", value: "count" },
                { label: "Value", value: "value" },
              ]}
              value={metric}
              onChange={(value) => setMetric(value as Metric)}
            />
          ) : undefined
        }
      />
      {section.status === "error" ? (
        <CardError label="Couldn't load the booking mix" />
      ) : (
        <BookingMixBody mix={section.data[period]} period={period} metric={metric} />
      )}
    </GlassCard>
  );
}

function BookingMixBody({
  mix,
  period,
  metric,
}: {
  mix: BookingMixEntry[];
  period: PerformancePeriod;
  metric: Metric;
}) {
  if (mix.every((entry) => entry.count === 0)) {
    return <CardEmpty message={`No bookings ${periodWindowPhrase(period)}`} hint="Flights, stays, activities and transport show here." />;
  }

  const maxCount = Math.max(1, ...mix.map((m) => m.count));
  const maxValue = Math.max(1, ...mix.map((m) => m.amountVnd));

  return (
    <ul className="flex flex-col gap-3">
      {mix.map((entry) => {
        const ratio = metric === "count" ? entry.count / maxCount : entry.amountVnd / maxValue;
        const display = metric === "count" ? `${entry.count}` : formatCompactVnd(entry.amountVnd);
        return (
          <li key={entry.bookingType} data-booking-type={entry.bookingType}>
            <div className="flex items-center justify-between text-xs">
              <span className="text-white/80 capitalize">{entry.bookingType}</span>
              <span className="font-medium text-white tabular-nums">{display}</span>
            </div>
            <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/15">
              <div
                className="bg-dash-accent h-full rounded-full transition-[width] duration-500"
                style={{ width: `${Math.round(ratio * 100)}%` }}
              />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

"use client";

import { useState } from "react";
import { PieChart } from "lucide-react";
import type { BookingMixEntry } from "@/lib/server/admin-dashboard";
import { formatCompactVnd } from "@/lib/format/vnd";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { SegmentToggle } from "./primitives/SegmentToggle";

type Metric = "count" | "value";

export function BookingMixCard({ mix }: { mix: BookingMixEntry[] }) {
  const [metric, setMetric] = useState<Metric>("count");
  const maxCount = Math.max(1, ...mix.map((m) => m.count));
  const maxValue = Math.max(1, ...mix.map((m) => m.amountVnd));

  return (
    <GlassCard>
      <div className="mb-4 flex items-center justify-between">
        <CardHeader label="Booking Mix" icon={PieChart} />
        <SegmentToggle
          options={[
            { label: "Bookings", value: "count" },
            { label: "Value", value: "value" },
          ]}
          value={metric}
          onChange={(value) => setMetric(value as Metric)}
        />
      </div>
      {mix.length === 0 ? (
        <p className="text-ink/50 text-sm">No bookings yet</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {mix.map((entry) => {
            const ratio = metric === "count" ? entry.count / maxCount : entry.amountVnd / maxValue;
            const display = metric === "count" ? `${entry.count}` : `${formatCompactVnd(entry.amountVnd)} ₫`;
            return (
              <li key={entry.bookingType}>
                <div className="flex items-center justify-between text-xs">
                  <span className="text-ink/70 capitalize">{entry.bookingType}</span>
                  <span className="text-ink font-medium">{display}</span>
                </div>
                <div className="mt-1 h-1.5 rounded-full bg-white/10">
                  <div
                    className="bg-primary h-full rounded-full transition-[width]"
                    style={{ width: `${Math.round(ratio * 100)}%` }}
                  />
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </GlassCard>
  );
}

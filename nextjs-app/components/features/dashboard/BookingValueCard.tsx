import { Wallet } from "lucide-react";
import type { BookingValueSummary } from "@/lib/server/admin-dashboard";
import { formatCompactVnd } from "@/lib/format/vnd";
import { BarMini } from "./primitives/BarMini";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";

/** "2026-11-08" -> "Nov 8", for the sparkline's tooltip label. */
function shortDay(isoDate: string): string {
  return new Date(`${isoDate}T00:00:00Z`).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

export function BookingValueCard({ summary }: { summary: BookingValueSummary }) {
  return (
    <GlassCard>
      <CardHeader label="Booking Value (Paid)" icon={Wallet} />
      <p className="text-ink font-display text-3xl tracking-wide">{formatCompactVnd(summary.paidVnd)} ₫</p>
      <p className="text-ink/50 mb-4 text-xs">{summary.paidCount} paid bookings, all time</p>
      <BarMini
        data={summary.daily.map((d) => ({ label: shortDay(d.day), value: d.amountVnd }))}
        valueFormat="compact-vnd"
      />
    </GlassCard>
  );
}

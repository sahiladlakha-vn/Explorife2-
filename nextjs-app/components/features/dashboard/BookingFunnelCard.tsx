import { Filter } from "lucide-react";
import type { BookingFunnel } from "@/lib/server/admin-dashboard";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { PillProgress } from "./primitives/PillProgress";

/** Each stage's bar width is relative to `toBook` (the funnel's widest/first stage). */
export function BookingFunnelCard({ funnel }: { funnel: BookingFunnel }) {
  const base = funnel.toBook || 1;

  return (
    <GlassCard>
      <CardHeader label="To Book → Booked → Paid" icon={Filter} />
      <div className="flex flex-col gap-3">
        <PillProgress label="To Book" percentage={100} displayValue={`${funnel.toBook}`} />
        <PillProgress label="Booked" percentage={(funnel.booked / base) * 100} displayValue={`${funnel.booked}`} />
        <PillProgress label="Paid" percentage={(funnel.paid / base) * 100} displayValue={`${funnel.paid}`} />
      </div>
    </GlassCard>
  );
}

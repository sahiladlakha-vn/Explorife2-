import { Compass } from "lucide-react";
import type { TripsInProgress } from "@/lib/server/admin-dashboard";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { RadialDial } from "./primitives/RadialDial";

export function TripsInProgressCard({ data }: { data: TripsInProgress }) {
  return (
    <GlassCard className="flex flex-col items-center text-center">
      <div className="w-full">
        <CardHeader label="Trips in Progress" icon={Compass} />
      </div>
      <RadialDial percentage={data.percentage} />
      <p className="text-ink/50 mt-3 text-xs">
        {data.activeCount} of {data.totalCount} trips active today
      </p>
    </GlassCard>
  );
}

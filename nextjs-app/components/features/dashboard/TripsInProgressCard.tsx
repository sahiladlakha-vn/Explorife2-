import { Compass } from "lucide-react";
import type { Section } from "@/lib/dashboard/section";
import type { TripsInProgress } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";
import { RadialDial } from "./primitives/RadialDial";

/** Dial of the share of all trips that are underway today (Vietnam calendar date). */
export function TripsInProgressCard({
  section,
  index = 0,
}: {
  section: Section<TripsInProgress>;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-trips-in-progress" className="flex flex-col">
      <CardHeader label="Trips in Progress" icon={Compass} />
      {section.status === "error" ? (
        <CardError label="Couldn't load trips" />
      ) : section.data.totalCount === 0 ? (
        <CardEmpty message="No trips yet" hint="Trips travelers create will be counted here." />
      ) : (
        <div className="flex flex-1 flex-col items-center justify-center text-center">
          <RadialDial percentage={section.data.percentage} />
          <p className="mt-3 text-xs text-white/70">
            {section.data.activeCount} of {section.data.totalCount} trips active today
          </p>
        </div>
      )}
    </GlassCard>
  );
}

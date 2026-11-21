import { ShieldCheck } from "lucide-react";
import { formatTurnaround } from "@/lib/dashboard/format";
import { periodWindowPhrase, type PerformancePeriod } from "@/lib/dashboard/periods";
import type { Section } from "@/lib/dashboard/section";
import type { ByPeriod, ModerationStats } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";
import { PillProgress } from "./primitives/PillProgress";

/** Share of attractions + restaurants created in the chosen window that are verified, and how long verification took. */
export function ModerationCard({
  section,
  period,
  index = 0,
}: {
  section: Section<ByPeriod<ModerationStats>>;
  period: PerformancePeriod;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-moderation">
      <CardHeader label="Moderation" icon={ShieldCheck} />
      {section.status === "error" ? (
        <CardError label="Couldn't load moderation stats" />
      ) : (
        <ModerationBody stats={section.data[period]} period={period} />
      )}
    </GlassCard>
  );
}

function ModerationBody({ stats, period }: { stats: ModerationStats; period: PerformancePeriod }) {
  if (stats.totalListings === 0) {
    return (
      <CardEmpty
        message={`No listings created ${periodWindowPhrase(period)}`}
        hint="Verification progress appears once attractions or restaurants are added."
      />
    );
  }

  return (
    <>
      <PillProgress label="Verified" percentage={stats.percentage} />
      <p className="mt-3 text-xs text-white/80">
        {stats.verifiedCount} verified · {stats.pendingCount} pending
      </p>
      <p className="text-xs text-white/70">
        {stats.avgTurnaroundHours === null
          ? "No verifications yet"
          : `${formatTurnaround(stats.avgTurnaroundHours)} average turnaround`}
      </p>
    </>
  );
}

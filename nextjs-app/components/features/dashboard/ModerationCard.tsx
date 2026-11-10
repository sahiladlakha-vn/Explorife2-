import { ShieldCheck } from "lucide-react";
import type { ModerationStats } from "@/lib/server/admin-dashboard";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { PillProgress } from "./primitives/PillProgress";

export function ModerationCard({ stats }: { stats: ModerationStats }) {
  return (
    <GlassCard>
      <CardHeader label="Moderation" icon={ShieldCheck} />
      <PillProgress label="Verified" percentage={stats.percentage} />
      <p className="text-ink/50 mt-3 text-xs">
        {stats.verifiedCount} verified · {stats.pendingCount} pending
      </p>
      <p className="text-ink/50 text-xs">
        {stats.avgTurnaroundHours === null
          ? "No verifications yet"
          : `${stats.avgTurnaroundHours.toFixed(1)}h average turnaround`}
      </p>
    </GlassCard>
  );
}

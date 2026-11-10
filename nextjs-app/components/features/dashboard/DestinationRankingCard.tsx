import { Trophy } from "lucide-react";
import type { DestinationRanking } from "@/lib/server/admin-dashboard";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";

/** Usage-ranked destinations from live trip data, falling back to the editorial CuratedCollection ranking when there's no usage data yet (e.g. a fresh environment). */
export function DestinationRankingCard({ ranking }: { ranking: DestinationRanking }) {
  const title = ranking.mode === "usage" ? "Top Destinations" : "Featured Destinations";

  return (
    <GlassCard>
      <CardHeader label={title} icon={Trophy} />
      {ranking.items.length === 0 ? (
        <p className="text-ink/50 text-sm">No destination data yet</p>
      ) : ranking.mode === "usage" ? (
        <ol className="flex flex-col gap-1.5">
          {ranking.items.map((item, i) => (
            <li key={item.location} className="flex items-center justify-between py-1">
              <span className="flex min-w-0 items-center gap-2">
                <span className="text-ink/40 w-4 shrink-0 text-xs">{i + 1}</span>
                <span className="text-ink truncate text-sm capitalize">{item.location}</span>
                {item.featured && (
                  <span className="bg-primary/15 text-primary shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold">
                    Featured
                  </span>
                )}
              </span>
              <span className="text-ink/50 shrink-0 text-xs">{item.tripCount} trips</span>
            </li>
          ))}
        </ol>
      ) : (
        <ol className="flex flex-col gap-1.5">
          {ranking.items.map((item, i) => (
            <li key={item.title} className="flex items-center gap-2 py-1">
              <span className="text-ink/40 w-4 shrink-0 text-xs">{i + 1}</span>
              <span className="text-ink truncate text-sm">{item.title}</span>
            </li>
          ))}
        </ol>
      )}
    </GlassCard>
  );
}

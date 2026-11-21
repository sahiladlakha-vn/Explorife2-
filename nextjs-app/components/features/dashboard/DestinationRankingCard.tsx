import { Trophy } from "lucide-react";
import { periodWindowPhrase, type PerformancePeriod } from "@/lib/dashboard/periods";
import type { Section } from "@/lib/dashboard/section";
import type { ByPeriod, DestinationRanking } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";

/**
 * Usage-ranked destinations from trips created in the chosen window, falling
 * back to the editorial CuratedCollection ranking when the environment has no
 * trips at all yet.
 */
export function DestinationRankingCard({
  section,
  period,
  index = 0,
}: {
  section: Section<ByPeriod<DestinationRanking>>;
  period: PerformancePeriod;
  index?: number;
}) {
  const ranking = section.status === "ok" ? section.data[period] : null;
  const title = ranking?.mode === "editorial" ? "Featured Destinations" : "Top Destinations";

  return (
    <GlassCard index={index} testId="card-destinations">
      <CardHeader label={title} icon={Trophy} />
      {ranking === null ? (
        <CardError label="Couldn't load destinations" />
      ) : ranking.items.length === 0 ? (
        <CardEmpty
          message={
            ranking.mode === "usage"
              ? `No trips created ${periodWindowPhrase(period)}`
              : "No destination data yet"
          }
          hint="Destinations are ranked by how many trips were created for them."
        />
      ) : ranking.mode === "usage" ? (
        <ol className="flex flex-col gap-1.5">
          {ranking.items.map((item, i) => (
            <li key={item.location} className="flex items-center justify-between gap-2 py-1">
              <span className="flex min-w-0 items-center gap-2">
                <span className="w-4 shrink-0 text-xs text-white/70 tabular-nums">{i + 1}</span>
                <span className="truncate text-sm text-white capitalize">{item.location}</span>
                {item.featured && (
                  <span className="ring-dash-accent/40 text-dash-accent shrink-0 rounded-full bg-black/40 px-2 py-0.5 text-[11px] font-semibold ring-1 ring-inset">
                    Featured
                  </span>
                )}
              </span>
              <span className="shrink-0 text-xs text-white/70 tabular-nums">
                {item.tripCount} {item.tripCount === 1 ? "trip" : "trips"}
              </span>
            </li>
          ))}
        </ol>
      ) : (
        <ol className="flex flex-col gap-1.5">
          {ranking.items.map((item, i) => (
            <li key={item.title} className="flex items-center gap-2 py-1">
              <span className="w-4 shrink-0 text-xs text-white/70 tabular-nums">{i + 1}</span>
              <span className="truncate text-sm text-white">{item.title}</span>
            </li>
          ))}
        </ol>
      )}
    </GlassCard>
  );
}

import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Period-over-period badge: emerald when up, rose when down. `percent` is null
 * when there is no baseline to compare against — then a non-zero current value
 * reads as "New", and a zero one shows nothing at all.
 */
export function ChangeBadge({
  percent,
  hasCurrent,
  comparedTo = "previous 7 days",
}: {
  percent: number | null;
  hasCurrent: boolean;
  comparedTo?: string;
}) {
  if (percent === null && !hasCurrent) return null;

  const tone =
    percent === null
      ? "neutral"
      : percent > 0
        ? "up"
        : percent < 0
          ? "down"
          : "neutral";

  const text = percent === null ? "New" : `${percent > 0 ? "+" : ""}${percent}%`;
  const Icon = tone === "up" ? ArrowUpRight : tone === "down" ? ArrowDownRight : Minus;
  const spoken =
    percent === null
      ? `New, no earlier ${comparedTo} to compare with`
      : `${Math.abs(percent)} percent ${tone === "down" ? "down" : tone === "up" ? "up" : "unchanged"} versus the ${comparedTo}`;

  return (
    <span
      data-tone={tone}
      title={`vs ${comparedTo}`}
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold tabular-nums",
        // A dark backing (not a tint of the accent itself) keeps the coloured text
        // readable wherever the scene behind the glass happens to be bright.
        tone === "up" && "ring-dash-positive/40 text-dash-positive bg-black/40 ring-1 ring-inset",
        tone === "down" && "ring-dash-negative/40 text-dash-negative bg-black/40 ring-1 ring-inset",
        tone === "neutral" && "bg-white/15 text-white",
      )}
    >
      <Icon className="h-3.5 w-3.5" aria-hidden="true" />
      <span aria-hidden="true">{text}</span>
      <span className="sr-only">{spoken}</span>
    </span>
  );
}

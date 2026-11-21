import type { CSSProperties } from "react";
import { cn } from "@/lib/utils";

/**
 * Horizontal pill progress bar; the fill grows from zero on load (CSS,
 * disabled under reduced motion). `displayValue` overrides the trailing text
 * (default `{percentage}%`) for callers like the funnel that show a raw count.
 */
export function PillProgress({
  label,
  percentage,
  displayValue,
  className,
  labelClassName,
  index = 0,
}: {
  label: string;
  percentage: number;
  displayValue?: string;
  className?: string;
  labelClassName?: string;
  /** Staggers the grow animation. */
  index?: number;
}) {
  const clamped = Math.min(100, Math.max(0, percentage));
  return (
    <div className={cn("flex items-center gap-3", className)}>
      <span className={cn("text-xs font-medium whitespace-nowrap text-white/80", labelClassName)}>{label}</span>
      <div
        role="progressbar"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(clamped)}
        className="h-2 flex-1 overflow-hidden rounded-full bg-white/15"
      >
        <div
          className="dash-bar-x bg-dash-accent h-full rounded-full transition-[width] duration-500"
          style={{ width: `${clamped}%`, "--i": index } as CSSProperties}
        />
      </div>
      <span className="min-w-9 text-right text-xs font-semibold whitespace-nowrap text-white tabular-nums">
        {displayValue ?? `${Math.round(clamped)}%`}
      </span>
    </div>
  );
}

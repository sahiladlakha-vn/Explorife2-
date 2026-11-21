import type { CSSProperties } from "react";
import { cn } from "@/lib/utils";

export interface ColumnBarItem {
  key: string;
  /** Short caption under the bar. */
  label: string;
  value: number;
  /** Full text for the hover tooltip, e.g. "Mon · 2,5 tr đ". */
  tooltip: string;
}

/**
 * Pure-CSS column chart (works in Server Components, no client JS). Bars grow
 * from zero on load, staggered, and stay still under reduced motion. The last
 * bar — today — is the amber one. Days with no value keep a thin stub so the
 * axis still reads as a continuous run of days.
 */
export function ColumnBars({
  items,
  ariaLabel,
  barAreaHeight = 88,
  labelEvery = 1,
}: {
  items: ColumnBarItem[];
  ariaLabel: string;
  barAreaHeight?: number;
  /** Caption every Nth column (the last one is always captioned). */
  labelEvery?: number;
}) {
  const max = Math.max(0, ...items.map((item) => item.value));

  return (
    <div role="img" aria-label={ariaLabel} className="flex items-stretch gap-1.5">
      {items.map((item, index) => {
        const isLast = index === items.length - 1;
        const heightPercent = max === 0 ? 0 : Math.max((item.value / max) * 100, item.value > 0 ? 6 : 0);
        const showLabel = index % labelEvery === 0 || isLast;

        return (
          <div key={item.key} title={item.tooltip} className="flex min-w-0 flex-1 flex-col items-center gap-1.5">
            <div className="flex w-full items-end" style={{ height: barAreaHeight }}>
              {item.value > 0 ? (
                <div
                  className={cn(
                    "dash-bar-y w-full rounded-t-lg",
                    isLast ? "bg-dash-accent" : "bg-white/40",
                  )}
                  style={{ height: `${heightPercent}%`, "--i": index } as CSSProperties}
                />
              ) : (
                <div className="h-[3px] w-full rounded-full bg-white/15" />
              )}
            </div>
            <span
              className={cn(
                "h-3 text-[11px] leading-3 whitespace-nowrap",
                isLast ? "font-semibold text-white" : "text-white/70",
                !showLabel && "invisible",
              )}
            >
              {item.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}

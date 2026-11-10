import { cn } from "@/lib/utils";

/** Horizontal pill progress bar. `displayValue` overrides the trailing text (default `{percentage}%`) for callers like a funnel that want to show a raw count instead. */
export function PillProgress({
  label,
  percentage,
  displayValue,
  className,
}: {
  label: string;
  percentage: number;
  displayValue?: string;
  className?: string;
}) {
  const clamped = Math.min(100, Math.max(0, percentage));
  return (
    <div className={cn("flex items-center gap-3", className)}>
      <span className="text-ink/70 text-xs font-medium whitespace-nowrap">{label}</span>
      <div className="h-2 flex-1 rounded-full bg-white/10">
        <div className="bg-primary h-full rounded-full transition-[width]" style={{ width: `${clamped}%` }} />
      </div>
      <span className="text-ink text-xs font-semibold whitespace-nowrap tabular-nums">
        {displayValue ?? `${Math.round(clamped)}%`}
      </span>
    </div>
  );
}

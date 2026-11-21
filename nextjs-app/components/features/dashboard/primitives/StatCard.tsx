import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { CornerArrow } from "./CornerArrow";
import { GlassCard } from "./GlassCard";

/** KPI-flavoured glass card: a muted label, one large light-weight number, an optional sublabel. */
export function StatCard({
  label,
  value,
  icon: Icon,
  sublabel,
  index = 0,
  testId,
}: {
  label: string;
  value: ReactNode;
  icon?: LucideIcon;
  sublabel?: ReactNode;
  index?: number;
  testId?: string;
}) {
  return (
    <GlassCard index={index} testId={testId} className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <span className="flex items-center gap-2 text-sm font-medium text-white/70">
          {Icon && (
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-white/10">
              <Icon className="text-dash-accent h-3.5 w-3.5" aria-hidden="true" />
            </span>
          )}
          {label}
        </span>
        <CornerArrow />
      </div>
      <div className="text-4xl font-light tracking-tight text-white tabular-nums">{value}</div>
      {sublabel && <div className="text-xs text-white/70">{sublabel}</div>}
    </GlassCard>
  );
}

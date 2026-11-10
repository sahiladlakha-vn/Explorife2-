import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { GlassCard } from "./GlassCard";

/** KPI-flavored `GlassCard`: a label, one big value, and an optional sublabel/icon. */
export function StatCard({
  label,
  value,
  icon: Icon,
  sublabel,
  className,
}: {
  label: string;
  value: ReactNode;
  icon?: LucideIcon;
  sublabel?: ReactNode;
  className?: string;
}) {
  return (
    <GlassCard className={cn("flex flex-col gap-3", className)}>
      <div className="flex items-center justify-between">
        <span className="text-ink/60 text-sm font-medium">{label}</span>
        {Icon && <Icon className="text-ink/40 h-4 w-4" aria-hidden="true" />}
      </div>
      <div className="text-ink font-display text-3xl tracking-wide">{value}</div>
      {sublabel && <div className="text-ink/50 text-xs">{sublabel}</div>}
    </GlassCard>
  );
}

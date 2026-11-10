import type { LucideIcon } from "lucide-react";

/** Shared label row for every dashboard `GlassCard` — kept separate only because it repeats across all nine cards. */
export function CardHeader({ label, icon: Icon }: { label: string; icon?: LucideIcon }) {
  return (
    <div className="mb-4 flex items-center gap-2">
      {Icon && <Icon className="text-primary h-4 w-4" aria-hidden="true" />}
      <h2 className="text-ink/80 text-sm font-semibold tracking-wide uppercase">{label}</h2>
    </div>
  );
}

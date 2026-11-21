import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { CornerArrow } from "./CornerArrow";

/**
 * Shared label row for every dashboard card: icon + title on the left; an
 * optional control (e.g. a toggle) and the inert corner arrow on the right.
 */
export function CardHeader({
  label,
  icon: Icon,
  trailing,
  arrow = true,
}: {
  label: string;
  icon?: LucideIcon;
  trailing?: ReactNode;
  arrow?: boolean;
}) {
  return (
    <div className="mb-4 flex items-center justify-between gap-2">
      <div className="flex min-w-0 items-center gap-2">
        {Icon && <Icon className="text-dash-accent h-4 w-4 shrink-0" aria-hidden="true" />}
        <h2 className="truncate text-sm font-semibold tracking-wide text-white/90 uppercase">{label}</h2>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {trailing}
        {arrow && <CornerArrow />}
      </div>
    </div>
  );
}

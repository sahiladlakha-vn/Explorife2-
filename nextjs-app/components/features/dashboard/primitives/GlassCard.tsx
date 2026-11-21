import type { CSSProperties, ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Base translucent surface for every `/admin/dashboard` card — see
 * `.glass-card` / `.glass-card-dark` in app/globals.css. `index` staggers the
 * entrance animation (a CSS custom property, so this stays a Server
 * Component); `variant="dark"` is the single dark card (Recent Bookings).
 */
export function GlassCard({
  children,
  className,
  variant = "glass",
  index = 0,
  lift = true,
  testId,
}: {
  children: ReactNode;
  className?: string;
  variant?: "glass" | "dark";
  index?: number;
  lift?: boolean;
  testId?: string;
}) {
  return (
    <div
      data-testid={testId}
      style={{ "--i": index } as CSSProperties}
      className={cn(
        variant === "dark" ? "glass-card-dark" : "glass-card",
        "dash-reveal h-full rounded-3xl p-5 text-white",
        lift && "dash-lift",
        className,
      )}
    >
      {children}
    </div>
  );
}

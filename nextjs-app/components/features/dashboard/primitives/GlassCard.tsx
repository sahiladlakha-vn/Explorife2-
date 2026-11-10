import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Base translucent surface for every `/admin/dashboard` card — see `.glass-card` in app/globals.css. */
export function GlassCard({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("glass-card rounded-3xl p-5 shadow-lg shadow-black/20", className)}>{children}</div>;
}

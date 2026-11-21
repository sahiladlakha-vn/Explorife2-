import { AlertTriangle } from "lucide-react";

/** Designed empty state: says what is missing, never a blank box. */
export function CardEmpty({ message, hint }: { message: string; hint?: string }) {
  return (
    <div
      role="status"
      data-state="empty"
      className="flex min-h-24 flex-col items-center justify-center gap-1 rounded-2xl border border-dashed border-white/20 px-4 py-6 text-center"
    >
      <p className="text-sm text-white/90">{message}</p>
      {hint && <p className="text-xs text-white/70">{hint}</p>}
    </div>
  );
}

/**
 * Error state for one card. The page settles each query separately, so a
 * failed query lands here without taking the rest of the dashboard down.
 */
export function CardError({ label }: { label?: string }) {
  return (
    <div
      role="alert"
      data-state="error"
      className="border-dash-negative/40 bg-dash-negative/10 flex min-h-24 flex-col items-center justify-center gap-2 rounded-2xl border px-4 py-6 text-center"
    >
      <AlertTriangle className="text-dash-negative h-5 w-5" aria-hidden="true" />
      <p className="text-sm text-white/90">{label ?? "Couldn't load this card"}</p>
      <p className="text-xs text-white/70">The rest of the dashboard is unaffected. Refresh to try again.</p>
    </div>
  );
}

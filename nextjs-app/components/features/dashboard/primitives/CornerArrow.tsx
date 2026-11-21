import { ArrowUpRight } from "lucide-react";

/**
 * Small round arrow-up-right in a card's corner. No destination screens exist
 * yet (only Dashboard is a real admin route), so — like the unbuilt nav pills
 * — it is visibly disabled and says so, instead of linking nowhere.
 */
export function CornerArrow() {
  return (
    <button
      type="button"
      aria-disabled="true"
      tabIndex={-1}
      title="Coming soon"
      className="flex h-8 w-8 shrink-0 cursor-not-allowed items-center justify-center rounded-full border border-white/20 bg-white/10 text-white opacity-50"
    >
      <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
      <span className="sr-only">Details (coming soon)</span>
    </button>
  );
}

import { PlusIcon } from "@/components/ui/icons";

/**
 * Icon-only on mobile, icon + label at ≥768px — a single component so the
 * responsive swap is CSS-only (no layout-shift between breakpoints). Step 4
 * is read-only (MIGRATION_PLAN.md §7), so this renders disabled.
 */
export function NewTripButton() {
  return (
    <button
      type="button"
      disabled
      aria-label="New trip — coming soon"
      title="Coming soon"
      className="bg-surface-raised text-text-muted flex h-9 shrink-0 cursor-not-allowed items-center gap-1.5 rounded-full px-3 opacity-50 md:px-4"
    >
      <PlusIcon className="h-4 w-4" />
      <span className="hidden text-sm font-medium md:inline">New Trip</span>
    </button>
  );
}

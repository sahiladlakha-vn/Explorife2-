import { CalendarIcon } from "@/components/ui/icons";

/** Step 4 is read-only (MIGRATION_PLAN.md §7) — renders disabled, wired up in a later step. */
export function CalendarIconButton() {
  return (
    <button
      type="button"
      disabled
      aria-label="Trip calendar — coming soon"
      title="Coming soon"
      className="text-text-muted flex h-9 w-9 shrink-0 cursor-not-allowed items-center justify-center rounded-full opacity-50"
    >
      <CalendarIcon className="h-5 w-5" />
    </button>
  );
}

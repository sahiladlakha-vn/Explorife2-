// Still a placeholder — `/` itself hasn't been built out yet (no redirect or
// real landing content). Real routes live at /auth, /profile/*, and
// /trips/[tripId]/* so far; this just proves the design tokens in
// app/globals.css (ported from lib/core/theme/app_theme.dart) are wired up.
// See MIGRATION_PLAN.md §7 for current step status.
export default function Home() {
  return (
    <div className="bg-bg text-ink flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="font-display text-ink text-5xl tracking-wide">
        ExploriFe
      </h1>
      <p className="text-ink/55 max-w-md">
        Next.js migration in progress — see{" "}
        <code className="bg-surface text-primary rounded px-1.5 py-0.5">
          MIGRATION_PLAN.md
        </code>{" "}
        for status.
      </p>
    </div>
  );
}

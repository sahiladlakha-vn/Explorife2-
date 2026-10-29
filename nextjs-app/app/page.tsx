// Step 2 placeholder — real routes land in Step 4 (shared layout) and beyond,
// per MIGRATION_PLAN.md §7. This just proves the design tokens in
// app/globals.css (ported from lib/core/theme/app_theme.dart) are wired up.
export default function Home() {
  return (
    <div className="bg-bg text-ink flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="font-display text-ink text-5xl tracking-wide">
        ExploriFe
      </h1>
      <p className="text-ink/55 max-w-md">
        Next.js foundation scaffold — Step 2 in progress. See{" "}
        <code className="bg-surface text-primary rounded px-1.5 py-0.5">
          MIGRATION_PLAN.md
        </code>{" "}
        for status.
      </p>
    </div>
  );
}

/**
 * Mirrors `HomeCta`'s pill-button height/shape so the `<Suspense>` fallback
 * on `/` reserves identical space — no layout shift once the real,
 * session-dependent CTA streams in. Same pattern as `AuthButtonsSkeleton`.
 */
export function HomeCtaSkeleton() {
  return (
    <div aria-hidden className="mt-2 flex animate-pulse flex-col items-center gap-2">
      <div className="bg-surface-raised h-9 w-32 rounded-full" />
    </div>
  );
}

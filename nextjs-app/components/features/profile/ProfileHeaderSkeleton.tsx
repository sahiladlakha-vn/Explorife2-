/**
 * Mirrors `ProfileTabs`'s exact box structure so the combined fallback
 * reserves the same total height as header + tabs together.
 */
export function ProfileTabsSkeleton() {
  return (
    <nav aria-hidden className="border-border flex animate-pulse gap-1 border-b px-4 md:px-6 lg:px-8">
      {["Overview", "My Trip", "Saved Gems", "My Stories", "Badges", "Settings"].map((label) => (
        <div key={label} className="shrink-0 border-b-2 border-transparent px-3 py-3">
          <div className="bg-surface-raised h-5 w-16 rounded text-sm font-medium">&nbsp;</div>
        </div>
      ))}
    </nav>
  );
}

/**
 * Mirrors `ProfileHeader`'s exact box structure (same padding/gap/line-height
 * classes) so the Suspense fallback reserves identical height — no layout
 * shift when the real header replaces it.
 */
export function ProfileHeaderSkeleton() {
  return (
    <div
      aria-hidden
      className="flex animate-pulse flex-col gap-4 px-4 py-6 md:flex-row md:items-center md:gap-6 md:px-6 lg:px-8"
    >
      <div className="bg-surface-raised h-16 w-16 shrink-0 rounded-full" />

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <div className="bg-surface-raised h-7 w-40 rounded text-xl font-semibold">&nbsp;</div>
          <div className="bg-surface-raised h-5 w-20 rounded-full px-2.5 py-0.5 text-xs font-medium">
            &nbsp;
          </div>
        </div>
        <dl className="mt-3 flex gap-6">
          {["Gems found", "Stories", "Countries"].map((label) => (
            <div key={label}>
              <dt className="text-text-muted text-xs">&nbsp;</dt>
              <dd className="bg-surface-raised h-6 w-8 rounded text-lg font-semibold">&nbsp;</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}

/**
 * Mirrors `OAuthProviderButton`'s height/shape so the `<Suspense>` fallback
 * on `/auth` reserves identical space — no layout shift once the real
 * buttons (which depend on `searchParams`) stream in.
 */
export function AuthButtonsSkeleton() {
  return (
    <div aria-hidden className="mt-6 flex animate-pulse flex-col gap-3">
      <div className="bg-surface-raised h-12 w-full rounded-xl" />
      <div className="bg-surface-raised h-12 w-full rounded-xl" />
    </div>
  );
}

import { Suspense } from "react";
import { AuthPageBody } from "@/components/features/auth/AuthPageBody";
import { AuthButtonsSkeleton } from "@/components/features/auth/AuthButtonsSkeleton";

/**
 * Static shell — the actual `searchParams` read lives in `AuthPageBody`, a
 * separate Server Component, so this stays prerenderable under Next's Cache
 * Components and only the button group streams in behind `<Suspense>`. Same
 * split as `ProfileLayout`/`TripLayout`.
 */
export default function AuthPage({
  searchParams,
}: {
  searchParams: Promise<{ redirect?: string; error?: string; provider?: string }>;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-12">
      <div className="w-full max-w-sm">
        <h1 className="font-display text-ink text-center text-4xl tracking-wide">Sign in</h1>
        <p className="text-text-muted mt-2 text-center text-sm">
          Save gems, sync your trips across devices, and pick up right where you left off.
        </p>

        <Suspense fallback={<AuthButtonsSkeleton />}>
          <AuthPageBody searchParams={searchParams} />
        </Suspense>
      </div>
    </div>
  );
}

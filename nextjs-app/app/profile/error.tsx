"use client";

import Link from "next/link";

/**
 * Error boundary scoped to `/profile/*` (Next.js `error.tsx` convention).
 * Several leaf pages under here still call the throwing `requireUser()`/
 * `requireTripAccess()` guards directly (lib/auth/permissions.ts,
 * lib/server/trips.ts) rather than the Step 5 `getOptionalUser()` + guest-view
 * pattern — this is the safety net for those until they're converted, so an
 * `AuthError` surfaces as a friendly retry/sign-in prompt instead of Next's
 * default crash screen. Must be a Client Component — Next's error boundary
 * contract.
 */
export default function ProfileError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16 text-center">
      <h1 className="font-display text-ink text-4xl tracking-wide">Something went wrong</h1>
      <p className="text-text-muted max-w-sm text-sm">
        We hit a snag loading your profile. Try again, or sign in if you&apos;ve been signed out.
      </p>
      <div className="mt-2 flex gap-3">
        <button
          type="button"
          onClick={reset}
          className="bg-surface-raised text-text rounded-full px-5 py-2 text-sm font-medium"
        >
          Try again
        </button>
        <Link
          href="/auth?redirect=%2Fprofile%2Foverview"
          className="bg-accent rounded-full px-5 py-2 text-sm font-medium text-white"
        >
          Sign in
        </Link>
      </div>
    </div>
  );
}

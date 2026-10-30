"use client";

/**
 * Root error boundary (Next.js `error.tsx` convention) — catches any
 * uncaught throw from a Server/Client Component render under `app/`,
 * including `AuthError`/`ForbiddenError` from `lib/auth/permissions.ts` that
 * a page calls directly rather than going through a `*OrRedirect` guard.
 * Deliberately shows a fixed, generic message rather than `error.message`:
 * that string can originate from Prisma/Supabase and isn't meant for
 * display. Must be a Client Component — Next's error boundary contract.
 */
export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16 text-center">
      <h1 className="font-display text-ink text-4xl tracking-wide">Something went wrong</h1>
      <p className="text-text-muted max-w-sm text-sm">
        We hit a snag loading this page. Please try again.
      </p>
      <button
        type="button"
        onClick={reset}
        className="bg-accent mt-2 rounded-full px-5 py-2 text-sm font-medium text-white"
      >
        Try again
      </button>
    </div>
  );
}

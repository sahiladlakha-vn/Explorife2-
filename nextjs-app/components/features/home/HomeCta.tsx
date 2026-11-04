import Link from "next/link";
import { getOptionalUser } from "@/lib/auth/permissions";

/**
 * Session-dependent part of `/` — isolated behind its own Server Component
 * so `app/page.tsx` can stay a static shell with no `cookies()` access
 * outside `<Suspense>` (Next's Cache Components otherwise refuses to
 * prerender it — same reasoning as `AuthPageBody`/`ProfileLayoutBody`).
 *
 * Unlike `SignOutPageBody`, this only branches on "is there a session at
 * all" — no guest-specific copy needed here, since `/profile/overview`'s
 * own guest view (built in Step 5) already handles the no-session case.
 */
export async function HomeCta() {
  const user = await getOptionalUser();

  if (user) {
    return (
      <Link
        href="/profile/overview"
        className="bg-accent mt-2 rounded-full px-5 py-2 text-sm font-medium text-white"
      >
        View your profile
      </Link>
    );
  }

  return (
    <div className="mt-2 flex flex-col items-center gap-2">
      <Link
        href="/auth?redirect=%2Fprofile%2Foverview"
        className="bg-accent rounded-full px-5 py-2 text-sm font-medium text-white"
      >
        Sign in
      </Link>
      <Link
        href="/profile/overview"
        className="text-text-muted text-sm underline underline-offset-2"
      >
        Browse without an account
      </Link>
    </div>
  );
}

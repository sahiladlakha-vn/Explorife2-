import type { ReactNode } from "react";
import { Suspense } from "react";
import Link from "next/link";
import { getOptionalUser } from "@/lib/auth/permissions";
import { getProfileHeaderData } from "@/lib/server/profiles";
import { ProfileHeader } from "./ProfileHeader";
import { ProfileTabs } from "./ProfileTabs";
import { ProfileTabsSkeleton } from "./ProfileHeaderSkeleton";

/**
 * Isolates the `cookies()`-dependent data fetch (via `getOptionalUser`)
 * behind its own Server Component so `app/profile/layout.tsx` can stay a
 * static shell and wrap just this piece in `<Suspense>`. Keeps the original
 * all-or-nothing behavior: with no profile row, tabs and children are
 * withheld too, not just the header.
 *
 * Uses `getOptionalUser()` rather than `requireUser()` (Step 5): a visitor
 * with no session at all is a normal, expected case here — Next's `<Link>`
 * prefetching requests `/profile/*` in the background from any page that
 * merely links there, so throwing/redirecting on "no session" would both
 * crash on a genuine zero-session visit and create guest work for every
 * prefetch. Render a guest view instead; `ensureAnonymousSession()` is only
 * ever called from inside a write Server Action, never here.
 *
 * `ProfileTabs` gets its own `<Suspense>` boundary here because it calls
 * `useSelectedLayoutSegment()`: on a `/profile/trips/[tripId]/*` route this
 * is a dynamic-param segment rendered per-request, which Next 16's
 * instant-navigation validation flags as URL data read outside Suspense
 * (docs: https://nextjs.org/docs/messages/blocking-prerender-client-hook).
 * Scoping the boundary to just the tabs — rather than this whole function's
 * output — keeps the header and `{children}` independently streamable.
 */
export async function ProfileLayoutBody({ children }: { children: ReactNode }) {
  const user = await getOptionalUser();

  if (!user) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 py-16 text-center">
        <p className="text-text text-lg font-medium">No trips or gems saved yet</p>
        <p className="text-text-muted max-w-sm text-sm">
          Sign in to save trips and gems, and pick up right where you left off on any device.
        </p>
        <Link
          href="/auth?redirect=%2Fprofile%2Foverview"
          className="bg-accent mt-2 rounded-full px-5 py-2 text-sm font-medium text-white"
        >
          Sign in
        </Link>
      </div>
    );
  }

  const { profile, leaderboardEntry } = await getProfileHeaderData(user.id);

  if (!profile) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center">
        <p className="text-text">No profile yet.</p>
        <p className="text-text-muted text-sm">Sign in to set up your profile.</p>
      </div>
    );
  }

  return (
    <>
      <ProfileHeader profile={profile} leaderboardEntry={leaderboardEntry} />
      <Suspense fallback={<ProfileTabsSkeleton />}>
        <ProfileTabs />
      </Suspense>
      <div className="flex flex-1 flex-col">{children}</div>
    </>
  );
}

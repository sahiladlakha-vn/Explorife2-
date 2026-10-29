import type { ReactNode } from "react";
import { requireUser } from "@/lib/auth/permissions";
import { getProfileHeaderData } from "@/lib/server/profiles";
import { ProfileHeader } from "./ProfileHeader";
import { ProfileTabs } from "./ProfileTabs";

/**
 * Isolates the `cookies()`-dependent data fetch (via `requireUser`) behind
 * its own Server Component so `app/profile/layout.tsx` can stay a static
 * shell and wrap just this piece in `<Suspense>`. Keeps the original
 * all-or-nothing behavior: with no profile row, tabs and children are
 * withheld too, not just the header.
 */
export async function ProfileLayoutBody({ children }: { children: ReactNode }) {
  const user = await requireUser();
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
      <ProfileTabs />
      <div className="flex flex-1 flex-col">{children}</div>
    </>
  );
}

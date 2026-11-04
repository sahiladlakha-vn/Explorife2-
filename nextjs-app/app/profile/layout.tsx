import type { ReactNode } from "react";
import { Suspense } from "react";
import { ProfileLayoutBody } from "@/components/features/profile/ProfileLayoutBody";
import {
  ProfileHeaderSkeleton,
  ProfileTabsSkeleton,
} from "@/components/features/profile/ProfileHeaderSkeleton";

/**
 * Shared shell for every `/profile/*` route (MIGRATION_PLAN.md §7 Step 4):
 * profile header + tabs render here, once, so navigating between tabs (and
 * down into `/profile/trips/[tripId]/*`) never remounts or repositions them
 * — only `children` (the active tab's page/layout) swaps.
 *
 * The `cookies()`-dependent fetch (via `requireUser`) lives in
 * `ProfileLayoutBody`, a separate Server Component, so this layout itself
 * stays a static shell and Next's Cache Components can prerender everything
 * outside the `<Suspense>` boundary. The fallback mirrors the real header +
 * tabs' box model so there's no layout shift once the real data streams in.
 */
export default function ProfileLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex flex-1 flex-col">
      <Suspense
        fallback={
          <>
            <ProfileHeaderSkeleton />
            <ProfileTabsSkeleton />
          </>
        }
      >
        <ProfileLayoutBody>{children}</ProfileLayoutBody>
      </Suspense>
    </div>
  );
}

import type { ReactNode } from "react";
import { Suspense } from "react";
import { TripLayoutBody } from "@/components/features/trips/TripLayoutBody";
import { TripHeaderSkeleton } from "@/components/features/trips/TripHeaderSkeleton";

/**
 * Shared shell for `/profile/trips/[tripId]/*`: re-checks access itself
 * (rather than trusting a leaf page rendered standalone) and renders the
 * trip switcher + sub-tabs once so they don't remount when the user moves
 * between trip/itinerary/dashboard/bookings.
 *
 * `params` and the `cookies()`-dependent fetch (via `requireTripAccess`) live
 * in `TripLayoutBody`, a separate Server Component, so this layout itself
 * stays a static shell and Next's Cache Components can prerender everything
 * outside the `<Suspense>` boundary. The fallback mirrors the real header's
 * box model so there's no layout shift once the real data streams in.
 *
 * `instant = false`, not a render-the-segment fix: this whole layout is
 * itself `{children}` of `ProfileLayoutBody`
 * (`components/features/profile/ProfileLayoutBody.tsx`), which withholds
 * `{children}` entirely when there's no session or profile row — so this
 * file is the dropped segment Next 16's instant-navigation validation
 * reports for every route under `/profile/trips/[tripId]/*` in that state
 * (docs: https://nextjs.org/docs/messages/instant-unrendered-segment). Same
 * "slot gated by authentication" case as the other `/profile/*` leaf pages;
 * see `app/profile/overview/page.tsx`'s comment for the full reasoning.
 */
export const instant = false;

export default function TripLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tripId: string }>;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <Suspense fallback={<TripHeaderSkeleton />}>
        <TripLayoutBody params={params}>{children}</TripLayoutBody>
      </Suspense>
    </div>
  );
}

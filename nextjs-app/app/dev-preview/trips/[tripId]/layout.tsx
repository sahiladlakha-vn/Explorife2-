import type { ReactNode } from "react";
import { Suspense } from "react";
import { notFound } from "next/navigation";
import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { getDevPreviewTrip, DEV_PREVIEW_TRIPS } from "@/lib/dev-preview/fixtures";
import { TripHeader } from "@/components/features/trips/TripHeader";
import { TripHeaderSkeleton } from "@/components/features/trips/TripHeaderSkeleton";

/**
 * Fixture-only mirror of `app/profile/trips/[tripId]/layout.tsx` — same
 * `TripHeader`, no auth/DB — so Playwright can assert the header's layout
 * (bounding box, responsive switcher variant) without a real session.
 * `assertDevPreviewEnabled` runs first and 404s outside dev/test, so this
 * whole subtree is unreachable in a production deploy.
 *
 * `params` is read in `DevPreviewTripLayoutBody` below, not here, and that
 * body is wrapped in `<Suspense>`: reading `params` directly in this layout
 * blocks prerendering per Next 16's instant-navigation validation (docs:
 * https://nextjs.org/docs/messages/blocking-prerender-runtime — "runtime
 * data during prerendering" from reading `params`/`searchParams`/`cookies`/
 * `headers` outside a Suspense boundary). Splitting it out lets this file
 * stay a static shell, same as the real `TripLayout`/`TripLayoutBody` split.
 */
export default function DevPreviewTripLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tripId: string }>;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <Suspense fallback={<TripHeaderSkeleton />}>
        <DevPreviewTripLayoutBody params={params}>{children}</DevPreviewTripLayoutBody>
      </Suspense>
    </div>
  );
}

async function DevPreviewTripLayoutBody({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tripId: string }>;
}) {
  assertDevPreviewEnabled();

  const { tripId } = await params;
  const trip = getDevPreviewTrip(tripId);
  if (!trip) notFound();

  return (
    <>
      <TripHeader trips={DEV_PREVIEW_TRIPS} activeTrip={trip} />
      <div className="flex flex-1 flex-col">{children}</div>
    </>
  );
}

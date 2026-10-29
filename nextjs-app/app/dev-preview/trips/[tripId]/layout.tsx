import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { getDevPreviewTrip, DEV_PREVIEW_TRIPS } from "@/lib/dev-preview/fixtures";
import { TripHeader } from "@/components/features/trips/TripHeader";

/**
 * Fixture-only mirror of `app/profile/trips/[tripId]/layout.tsx` — same
 * `TripHeader`, no auth/DB — so Playwright can assert the header's layout
 * (bounding box, responsive switcher variant) without a real session.
 * `assertDevPreviewEnabled` runs first and 404s outside dev/test, so this
 * whole subtree is unreachable in a production deploy.
 */
export default async function DevPreviewTripLayout({
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
    <div className="flex flex-1 flex-col">
      <TripHeader trips={DEV_PREVIEW_TRIPS} activeTrip={trip} />
      <div className="flex flex-1 flex-col">{children}</div>
    </div>
  );
}

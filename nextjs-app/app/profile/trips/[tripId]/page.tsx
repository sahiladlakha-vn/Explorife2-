import { redirect } from "next/navigation";

/** `/profile/trips/[tripId]` with no sub-tab segment lands on the trip overview. */
/**
 * `instant = false` — `TripLayoutBody` (`components/features/trips/TripLayoutBody.tsx`)
 * withholds `{children}` (this page) when `getOptionalUser()` finds no
 * session, a gate independent of `ProfileLayoutBody`'s outer one already
 * handled on `[tripId]/layout.tsx`. Same "slot gated by authentication" case
 * (see `app/profile/overview/page.tsx`'s comment) — each independently
 * gating layer needs its own marker, confirmed empirically: marking the
 * parent layout `instant=false` did not suppress this leaf's own warning.
 */
export const instant = false;

export default async function TripIndexPage({
  params,
}: {
  params: Promise<{ tripId: string }>;
}) {
  const { tripId } = await params;
  redirect(`/profile/trips/${tripId}/trip`);
}

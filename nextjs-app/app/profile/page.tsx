import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/permissions";
import { getActiveTripId } from "@/lib/server/trips";

/**
 * Redirect target for the old Flutter tab-index routes (MIGRATION_PLAN.md
 * §1): `/profile?tab=N` for N in 0-5. Confirmed via a repo-wide search (see
 * MIGRATION_PLAN.md §7 Step 4 notes) that `?tab=` is the ONLY externally
 * reachable shape — `tripId`/`segment` were only ever carried in-memory via
 * the Flutter `ProfileDeepLink` object (GoRouter `extra:`), never
 * serialized into a URL, so there's nothing else to parse here.
 */
export default async function ProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string | string[] }>;
}) {
  const { tab: tabParam } = await searchParams;
  const tabValue = Array.isArray(tabParam) ? tabParam[0] : tabParam;
  const tab = tabValue !== undefined ? Number(tabValue) : NaN;

  if (tab === 1) {
    const user = await requireUser();
    const activeTripId = await getActiveTripId(user.id);
    redirect(activeTripId ? `/profile/trips/${activeTripId}/trip` : "/profile/trips");
  }

  const target: Record<number, string> = {
    0: "/profile/overview",
    2: "/profile/saved",
    3: "/profile/stories",
    4: "/profile/badges",
    5: "/profile/settings",
  };

  redirect(target[tab] ?? "/profile/overview");
}

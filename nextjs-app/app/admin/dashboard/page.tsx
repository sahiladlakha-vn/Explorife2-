import { requireAdminOrRedirect } from "@/lib/auth/guards";
import { failed, ok, type Section } from "@/lib/dashboard/section";
import {
  getBookingFunnel,
  getBookingMixByPeriod,
  getBookingValueSummary,
  getBookingVelocity,
  getDestinationRankingByPeriod,
  getModerationByPeriod,
  getModerationStats,
  getRecentBookings,
  getTotalUsers,
  getTripsInProgress,
  getUpcomingBookingCoverage,
  getUpcomingWeek,
} from "@/lib/server/admin-dashboard";
import { getAdminDisplayName } from "@/lib/server/admin-profile";
import { AdminDashboard } from "@/components/features/dashboard/AdminDashboard";

/**
 * `requireAdminOrRedirect` reads `cookies()` (via `getCurrentUser`) outside
 * `<Suspense>` to decide whether to redirect — same `instant = false` need as
 * `app/dev-preview/protected/page.tsx` (see its comment for the full
 * rationale): this page's entire body depends on that request-time check, so
 * there's no static shell worth prerendering first.
 */
export const instant = false;

/**
 * Turns one query into a `Section` that can never reject: a failure is logged
 * and becomes an error state on that card only, instead of an exception out of
 * `Promise.all` that would drop the whole page into the root error boundary.
 */
async function settle<T>(label: string, load: Promise<T>): Promise<Section<T>> {
  try {
    return ok(await load);
  } catch (error) {
    console.error(`[admin-dashboard] ${label} failed`, error);
    return failed<T>();
  }
}

export default async function AdminDashboardPage() {
  const { user, role } = await requireAdminOrRedirect("/admin/dashboard");

  const [
    name,
    totalUsers,
    trips,
    upcomingBookingCoverage,
    moderation,
    bookingValue,
    bookingVelocity,
    bookingFunnel,
    upcomingWeek,
    recentBookings,
    destinations,
    bookingMix,
    moderationByPeriod,
  ] = await Promise.all([
    // The greeting is a nicety: if the profile lookup fails, just say "Welcome back".
    getAdminDisplayName(user.id).catch((error: unknown) => {
      console.error("[admin-dashboard] admin display name failed", error);
      return null;
    }),
    settle("totalUsers", getTotalUsers()),
    settle("trips", getTripsInProgress()),
    settle("upcomingBookingCoverage", getUpcomingBookingCoverage()),
    settle("moderation", getModerationStats()),
    settle("bookingValue", getBookingValueSummary()),
    settle("bookingVelocity", getBookingVelocity()),
    settle("bookingFunnel", getBookingFunnel()),
    settle("upcomingWeek", getUpcomingWeek()),
    settle("recentBookings", getRecentBookings()),
    settle("destinations", getDestinationRankingByPeriod()),
    settle("bookingMix", getBookingMixByPeriod()),
    settle("moderationByPeriod", getModerationByPeriod()),
  ]);

  return (
    <AdminDashboard
      data={{
        admin: { role, name },
        totalUsers,
        trips,
        upcomingBookingCoverage,
        moderation,
        bookingValue,
        bookingVelocity,
        bookingFunnel,
        upcomingWeek,
        recentBookings,
        destinations,
        bookingMix,
        moderationByPeriod,
      }}
    />
  );
}

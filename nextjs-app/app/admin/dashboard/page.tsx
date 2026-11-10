import { requireAdminOrRedirect } from "@/lib/auth/guards";
import {
  getBookingFunnel,
  getBookingMix,
  getBookingValueSummary,
  getDestinationRanking,
  getModerationStats,
  getRecentBookings,
  getTotalUsers,
  getTripsInProgress,
  getUpcomingBookingCoverage,
  getUpcomingTrips,
} from "@/lib/server/admin-dashboard";
import { AdminDashboard } from "@/components/features/dashboard/AdminDashboard";

/**
 * `requireAdminOrRedirect` reads `cookies()` (via `getCurrentUser`) outside
 * `<Suspense>` to decide whether to redirect — same `instant = false` need as
 * `app/dev-preview/protected/page.tsx` (see its comment for the full
 * rationale): this page's entire body depends on that request-time check, so
 * there's no static shell worth prerendering first.
 */
export const instant = false;

export default async function AdminDashboardPage() {
  const { user, role } = await requireAdminOrRedirect("/admin/dashboard");

  const [
    totalUsers,
    tripsInProgress,
    upcomingBookingCoverage,
    moderation,
    bookingValue,
    bookingFunnel,
    upcomingTrips,
    recentBookings,
    bookingMix,
    destinationRanking,
  ] = await Promise.all([
    getTotalUsers(),
    getTripsInProgress(),
    getUpcomingBookingCoverage(),
    getModerationStats(),
    getBookingValueSummary(),
    getBookingFunnel(),
    getUpcomingTrips(),
    getRecentBookings(),
    getBookingMix(),
    getDestinationRanking(),
  ]);

  return (
    <AdminDashboard
      data={{
        admin: { role, email: user.email ?? "" },
        totalUsers,
        tripsInProgress,
        upcomingBookingCoverage,
        moderation,
        bookingValue,
        bookingFunnel,
        upcomingTrips,
        recentBookings,
        bookingMix,
        destinationRanking,
      }}
    />
  );
}

import type { Role } from "@/lib/auth/permissions";
import type {
  BookingFunnel,
  BookingMixEntry,
  BookingValueSummary,
  DestinationRanking,
  ModerationStats,
  RecentBookingItem,
  TripsInProgress,
  UpcomingBookingCoverage,
  UpcomingTripItem,
} from "@/lib/server/admin-dashboard";
import { BookingFunnelCard } from "./BookingFunnelCard";
import { BookingMixCard } from "./BookingMixCard";
import { BookingValueCard } from "./BookingValueCard";
import { DashboardHeader } from "./DashboardHeader";
import { DashboardTopBar } from "./DashboardTopBar";
import { DestinationRankingCard } from "./DestinationRankingCard";
import { ModerationCard } from "./ModerationCard";
import { RecentBookingsCard } from "./RecentBookingsCard";
import { TripsInProgressCard } from "./TripsInProgressCard";
import { UpcomingTripsCard } from "./UpcomingTripsCard";

/**
 * Single prop bag mirroring `Promise.all`'s result shape in
 * app/admin/dashboard/page.tsx, so this component — the actual visual shell
 * — can be rendered unmodified from either that real page or the
 * `/dev-preview/admin/dashboard` fixture mirror.
 */
export interface AdminDashboardData {
  admin: { role: Role; email: string };
  totalUsers: number;
  tripsInProgress: TripsInProgress;
  upcomingBookingCoverage: UpcomingBookingCoverage;
  moderation: ModerationStats;
  bookingValue: BookingValueSummary;
  bookingFunnel: BookingFunnel;
  upcomingTrips: UpcomingTripItem[];
  recentBookings: RecentBookingItem[];
  bookingMix: BookingMixEntry[];
  destinationRanking: DestinationRanking;
}

export function AdminDashboard({ data }: { data: AdminDashboardData }) {
  return (
    <div className="admin-dashboard-backdrop min-h-screen px-4 py-6 md:px-6 lg:px-8">
      <div className="mx-auto flex max-w-7xl flex-col gap-6">
        <DashboardTopBar admin={data.admin} />

        <DashboardHeader
          totalUsers={data.totalUsers}
          totalTrips={data.tripsInProgress.totalCount}
          paidVnd={data.bookingValue.paidVnd}
          upcomingBookingCoveragePercentage={data.upcomingBookingCoverage.percentage}
          moderationPercentage={data.moderation.percentage}
        />

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <BookingValueCard summary={data.bookingValue} />
          </div>
          <TripsInProgressCard data={data.tripsInProgress} />
          <BookingFunnelCard funnel={data.bookingFunnel} />
          <UpcomingTripsCard trips={data.upcomingTrips} />
          <div className="lg:col-span-1">
            <RecentBookingsCard bookings={data.recentBookings} />
          </div>
        </div>

        <section className="flex flex-col gap-4">
          <h2 className="text-ink/80 text-sm font-semibold tracking-wide uppercase">Performance Overview</h2>
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            <ModerationCard stats={data.moderation} />
            <BookingMixCard mix={data.bookingMix} />
            <DestinationRankingCard ranking={data.destinationRanking} />
          </div>
        </section>
      </div>
    </div>
  );
}

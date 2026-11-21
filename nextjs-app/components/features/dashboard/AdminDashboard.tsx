import type { Role } from "@/lib/auth/permissions";
import type { Section } from "@/lib/dashboard/section";
import type {
  BookingFunnel,
  BookingMixEntry,
  BookingValueSummary,
  BookingVelocity,
  ByPeriod,
  DestinationRanking,
  ModerationStats,
  RecentBookingItem,
  TripsInProgress,
  UpcomingBookingCoverage,
  UpcomingWeek,
} from "@/lib/dashboard/types";
import { cn } from "@/lib/utils";
import { BookingFunnelCard } from "./BookingFunnelCard";
import { BookingValueCard } from "./BookingValueCard";
import { BookingVelocityCard } from "./BookingVelocityCard";
import { DashboardBackdrop } from "./DashboardBackdrop";
import { DashboardHeader } from "./DashboardHeader";
import { DashboardTopBar } from "./DashboardTopBar";
import { dashboardFont } from "./fonts";
import { PerformanceOverview } from "./PerformanceOverview";
import { RecentBookingsCard } from "./RecentBookingsCard";
import { TripsInProgressCard } from "./TripsInProgressCard";
import { UpcomingTripsCard } from "./UpcomingTripsCard";

/**
 * Single prop bag mirroring `Promise.all`'s result shape in
 * app/admin/dashboard/page.tsx, so this component — the actual visual shell —
 * can be rendered unmodified from either that real page or the
 * `/dev-preview/admin/dashboard` fixture mirror. Every card's data is a
 * `Section`, i.e. loaded or "failed to load", so one failing query shows an
 * error state on that card alone.
 */
export interface AdminDashboardData {
  admin: { role: Role; name: string | null };
  totalUsers: Section<number>;
  trips: Section<TripsInProgress>;
  upcomingBookingCoverage: Section<UpcomingBookingCoverage>;
  /** All-time, for the header pill. */
  moderation: Section<ModerationStats>;
  bookingValue: Section<BookingValueSummary>;
  bookingVelocity: Section<BookingVelocity>;
  bookingFunnel: Section<BookingFunnel>;
  upcomingWeek: Section<UpcomingWeek>;
  recentBookings: Section<RecentBookingItem[]>;
  destinations: Section<ByPeriod<DestinationRanking>>;
  bookingMix: Section<ByPeriod<BookingMixEntry[]>>;
  moderationByPeriod: Section<ByPeriod<ModerationStats>>;
}

export function AdminDashboard({ data }: { data: AdminDashboardData }) {
  return (
    <div
      className={cn(
        dashboardFont.variable,
        "admin-dashboard font-dash relative isolate min-h-screen px-4 py-6 text-white md:px-6 lg:px-8",
      )}
    >
      <DashboardBackdrop />

      <div className="mx-auto flex max-w-7xl flex-col gap-6">
        <DashboardTopBar admin={data.admin} />

        <main className="flex flex-col gap-6">
          <DashboardHeader
            name={data.admin.name}
            totalUsers={data.totalUsers}
            trips={data.trips}
            coverage={data.upcomingBookingCoverage}
            moderation={data.moderation}
            bookingValue={data.bookingValue}
          />

          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            <div className="lg:col-span-2">
              <BookingValueCard section={data.bookingValue} index={4} />
            </div>
            <TripsInProgressCard section={data.trips} index={5} />
            <BookingVelocityCard section={data.bookingVelocity} index={6} />
            <BookingFunnelCard section={data.bookingFunnel} index={7} />
            <div className="lg:row-span-2">
              <RecentBookingsCard section={data.recentBookings} index={8} />
            </div>
            <div className="lg:col-span-2">
              <UpcomingTripsCard section={data.upcomingWeek} index={9} />
            </div>
          </div>

          <PerformanceOverview
            destinations={data.destinations}
            bookingMix={data.bookingMix}
            moderation={data.moderationByPeriod}
          />
        </main>
      </div>
    </div>
  );
}

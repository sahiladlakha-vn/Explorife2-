import { MapPinned, Users, Wallet } from "lucide-react";
import { AnimatedNumber } from "./primitives/AnimatedNumber";
import { GlassCard } from "./primitives/GlassCard";
import { Greeting } from "./primitives/Greeting";
import { PillProgress } from "./primitives/PillProgress";
import { StatCard } from "./primitives/StatCard";

export function DashboardHeader({
  totalUsers,
  totalTrips,
  paidVnd,
  upcomingBookingCoveragePercentage,
  moderationPercentage,
}: {
  totalUsers: number;
  totalTrips: number;
  paidVnd: number;
  upcomingBookingCoveragePercentage: number;
  moderationPercentage: number;
}) {
  return (
    <section className="grid grid-cols-1 gap-4 lg:grid-cols-[2fr_1fr_1fr_1fr]">
      <GlassCard className="flex flex-col justify-center gap-4">
        <div>
          <Greeting />
          <h1 className="font-display text-ink text-3xl tracking-wide">Welcome back</h1>
        </div>
        <div className="flex flex-col gap-3 sm:flex-row sm:gap-6">
          <PillProgress
            label="Upcoming trips booked"
            percentage={upcomingBookingCoveragePercentage}
            className="sm:w-64"
          />
          <PillProgress label="Listings verified" percentage={moderationPercentage} className="sm:w-64" />
        </div>
      </GlassCard>

      <StatCard label="Total Users" value={<AnimatedNumber value={totalUsers} />} icon={Users} />
      <StatCard label="Total Trips" value={<AnimatedNumber value={totalTrips} />} icon={MapPinned} />
      <StatCard
        label="Booking Value"
        value={<AnimatedNumber value={paidVnd} format="compact-vnd" />}
        icon={Wallet}
      />
    </section>
  );
}

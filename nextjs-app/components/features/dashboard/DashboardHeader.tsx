import { MapPinned, Users, Wallet } from "lucide-react";
import type { Section } from "@/lib/dashboard/section";
import type {
  BookingValueSummary,
  ModerationStats,
  TripsInProgress,
  UpcomingBookingCoverage,
} from "@/lib/dashboard/types";
import { AnimatedNumber } from "./primitives/AnimatedNumber";
import { GlassCard } from "./primitives/GlassCard";
import { Greeting } from "./primitives/Greeting";
import { PillProgress } from "./primitives/PillProgress";
import { StatCard } from "./primitives/StatCard";

/** A pill's props from a settled section: the real percentage, or an empty bar with "—" if loading it failed. */
function pillValue<T>(section: Section<T>, pick: (data: T) => number) {
  return section.status === "ok"
    ? { percentage: pick(section.data) }
    : { percentage: 0, displayValue: "—" };
}

const UNAVAILABLE = <span aria-label="Unavailable">—</span>;

export function DashboardHeader({
  name,
  totalUsers,
  trips,
  coverage,
  moderation,
  bookingValue,
}: {
  name: string | null;
  totalUsers: Section<number>;
  trips: Section<TripsInProgress>;
  coverage: Section<UpcomingBookingCoverage>;
  moderation: Section<ModerationStats>;
  bookingValue: Section<BookingValueSummary>;
}) {
  return (
    <section className="grid grid-cols-1 gap-4 sm:grid-cols-3 lg:grid-cols-[2fr_1fr_1fr_1fr]">
      <GlassCard
        index={0}
        testId="card-welcome"
        className="flex flex-col justify-center gap-5 sm:col-span-3 lg:col-span-1"
      >
        <div>
          <Greeting />
          <h1 className="text-3xl font-light tracking-tight break-words">
            Welcome back
            {name ? (
              <>
                , <span className="font-semibold">{name}</span>
              </>
            ) : null}
          </h1>
        </div>
        <div className="flex flex-col gap-3">
          <PillProgress
            label="Upcoming trips booked"
            labelClassName="w-40"
            index={0}
            {...pillValue(coverage, (c) => c.percentage)}
          />
          <PillProgress
            label="Trips completed"
            labelClassName="w-40"
            index={1}
            {...pillValue(trips, (t) => t.completedPercentage)}
          />
          <PillProgress
            label="Listings verified"
            labelClassName="w-40"
            index={2}
            {...pillValue(moderation, (m) => m.percentage)}
          />
        </div>
      </GlassCard>

      <StatCard
        label="Total Users"
        icon={Users}
        index={1}
        testId="kpi-total-users"
        value={totalUsers.status === "ok" ? <AnimatedNumber value={totalUsers.data} /> : UNAVAILABLE}
      />
      <StatCard
        label="Active Trips"
        icon={MapPinned}
        index={2}
        testId="kpi-active-trips"
        value={trips.status === "ok" ? <AnimatedNumber value={trips.data.activeCount} /> : UNAVAILABLE}
        sublabel={trips.status === "ok" ? `of ${trips.data.totalCount} trips` : "Unavailable"}
      />
      <StatCard
        label="Booking Value"
        icon={Wallet}
        index={3}
        testId="kpi-booking-value"
        value={
          bookingValue.status === "ok" ? (
            <AnimatedNumber value={bookingValue.data.paidVnd} format="compact-vnd" />
          ) : (
            UNAVAILABLE
          )
        }
        sublabel={bookingValue.status === "ok" ? "Paid, logged by travelers" : "Unavailable"}
      />
    </section>
  );
}

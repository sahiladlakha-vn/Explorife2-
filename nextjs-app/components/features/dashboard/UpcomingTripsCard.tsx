import { CalendarClock } from "lucide-react";
import type { UpcomingTripItem } from "@/lib/server/admin-dashboard";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { WeekTimeline } from "./primitives/WeekTimeline";

function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export function UpcomingTripsCard({ trips }: { trips: UpcomingTripItem[] }) {
  return (
    <GlassCard>
      <CardHeader label="Upcoming Trips" icon={CalendarClock} />
      <WeekTimeline
        items={trips.map((trip) => ({
          id: trip.id,
          title: trip.name,
          subtitle: trip.location,
          startLabel: shortDate(trip.startDate),
          endLabel: shortDate(trip.endDate),
        }))}
        emptyLabel="No upcoming trips"
      />
    </GlassCard>
  );
}

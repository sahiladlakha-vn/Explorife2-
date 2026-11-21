import { CalendarClock } from "lucide-react";
import { monthDayShort } from "@/lib/dashboard/booking-trends";
import type { Section } from "@/lib/dashboard/section";
import type { UpcomingWeek } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";
import { WeekStrip } from "./primitives/WeekStrip";

/** This week (Mon–Sun, Vietnam) with each trip drawn from its start day to its end day. */
export function UpcomingTripsCard({
  section,
  index = 0,
}: {
  section: Section<UpcomingWeek>;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-upcoming-trips">
      <CardHeader label="Upcoming Trips" icon={CalendarClock} />
      {section.status === "error" ? (
        <CardError label="Couldn't load upcoming trips" />
      ) : (
        <UpcomingTripsBody week={section.data} />
      )}
    </GlassCard>
  );
}

function UpcomingTripsBody({ week }: { week: UpcomingWeek }) {
  const { trips, nextTrip } = week;

  return (
    <>
      <WeekStrip weekStart={week.weekStart} today={week.today} trips={trips} />
      {trips.length === 0 && (
        <div className="mt-3">
          <CardEmpty
            message="No trips this week"
            hint={nextTrip ? undefined : "Trips appear here from the day they start."}
          />
        </div>
      )}
      {nextTrip && (
        <p className="mt-3 truncate text-xs text-white/80">
          <span className="text-white/70">Next up:</span>{" "}
          <span className="font-medium text-white">{nextTrip.name}</span> · {monthDayShort(nextTrip.startDate)} →{" "}
          {monthDayShort(nextTrip.endDate)}
        </p>
      )}
    </>
  );
}

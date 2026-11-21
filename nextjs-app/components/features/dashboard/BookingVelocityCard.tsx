import { Activity } from "lucide-react";
import { monthDayShort } from "@/lib/dashboard/booking-trends";
import type { Section } from "@/lib/dashboard/section";
import type { BookingVelocity } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { ColumnBars } from "./primitives/ColumnBars";
import { GlassCard } from "./primitives/GlassCard";

/** How many bookings were created each day over the last 14 days (any status). */
export function BookingVelocityCard({
  section,
  index = 0,
}: {
  section: Section<BookingVelocity>;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-booking-velocity">
      <CardHeader label="Booking Velocity" icon={Activity} />
      {section.status === "error" ? (
        <CardError label="Couldn't load booking velocity" />
      ) : (
        <BookingVelocityBody velocity={section.data} />
      )}
    </GlassCard>
  );
}

function BookingVelocityBody({ velocity }: { velocity: BookingVelocity }) {
  const { daily, total } = velocity;

  if (total === 0) {
    return (
      <CardEmpty
        message="No bookings in the last 14 days"
        hint="New bookings will show up here day by day."
      />
    );
  }

  const average = daily.length === 0 ? 0 : total / daily.length;
  const first = daily[0]!.day;
  const last = daily[daily.length - 1]!.day;

  return (
    <>
      <p className="text-4xl font-light tracking-tight tabular-nums">{total}</p>
      <p className="mb-5 text-xs text-white/70">
        {total === 1 ? "booking" : "bookings"} in the last 14 days · {average.toFixed(1)} a day
      </p>
      <ColumnBars
        ariaLabel="Bookings created per day, last 14 days"
        barAreaHeight={72}
        items={daily.map((day) => ({
          key: day.day,
          // Day of month only: 14 columns are too narrow for month names.
          label: String(Number(day.day.slice(8, 10))),
          value: day.count,
          tooltip: `${monthDayShort(day.day)} · ${day.count} ${day.count === 1 ? "booking" : "bookings"}`,
        }))}
      />
      <p className="mt-2 text-center text-[11px] text-white/65">
        {monthDayShort(first)} – {monthDayShort(last)}
      </p>
    </>
  );
}

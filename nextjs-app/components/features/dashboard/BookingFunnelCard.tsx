import { Filter } from "lucide-react";
import type { Section } from "@/lib/dashboard/section";
import type { BookingFunnel } from "@/lib/dashboard/types";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";
import { PillProgress } from "./primitives/PillProgress";

const share = (part: number, whole: number): number =>
  whole === 0 ? 0 : Math.round((part / whole) * 100);

/**
 * Cumulative funnel: To Book = every booking, Booked = booked + paid, Paid =
 * paid. Each bar is sized relative to To Book, the widest stage.
 */
export function BookingFunnelCard({
  section,
  index = 0,
}: {
  section: Section<BookingFunnel>;
  index?: number;
}) {
  return (
    <GlassCard index={index} testId="card-booking-funnel">
      <CardHeader label="To Book → Booked → Paid" icon={Filter} />
      {section.status === "error" ? (
        <CardError label="Couldn't load the booking funnel" />
      ) : section.data.toBook === 0 ? (
        <CardEmpty message="No bookings yet" hint="Each booking moves To Book → Booked → Paid." />
      ) : (
        <FunnelBody funnel={section.data} />
      )}
    </GlassCard>
  );
}

function FunnelBody({ funnel }: { funnel: BookingFunnel }) {
  return (
    <>
      <div className="flex flex-col gap-3">
        <PillProgress
          label="To Book"
          labelClassName="w-16"
          percentage={100}
          displayValue={`${funnel.toBook}`}
          index={0}
        />
        <PillProgress
          label="Booked"
          labelClassName="w-16"
          percentage={share(funnel.booked, funnel.toBook)}
          displayValue={`${funnel.booked}`}
          index={1}
        />
        <PillProgress
          label="Paid"
          labelClassName="w-16"
          percentage={share(funnel.paid, funnel.toBook)}
          displayValue={`${funnel.paid}`}
          index={2}
        />
      </div>
      <p className="mt-4 text-xs text-white/70">
        {share(funnel.booked, funnel.toBook)}% booked · {share(funnel.paid, funnel.booked)}% of booked paid
      </p>
    </>
  );
}

import { Receipt } from "lucide-react";
import { vietnamDayShort } from "@/lib/dashboard/format";
import type { Section } from "@/lib/dashboard/section";
import type { RecentBookingItem } from "@/lib/dashboard/types";
import { formatCompactVnd } from "@/lib/format/vnd";
import { cn } from "@/lib/utils";
import { CardHeader } from "./primitives/CardHeader";
import { CardEmpty, CardError } from "./primitives/CardNotice";
import { GlassCard } from "./primitives/GlassCard";

const STATUS_LABEL: Record<string, string> = { to_book: "To Book", booked: "Booked", paid: "Paid" };
const STATUS_CLASS: Record<string, string> = {
  to_book: "bg-white/15 text-white/90",
  booked: "bg-dash-accent/20 text-dash-accent",
  paid: "bg-dash-positive/20 text-dash-positive",
};

/**
 * The dark card. Trip name, booking type, amount, status and date only —
 * never the booking creator's e-mail or phone. The "x/y paid" counter is the
 * number of paid bookings among the ones listed here.
 */
export function RecentBookingsCard({
  section,
  index = 0,
}: {
  section: Section<RecentBookingItem[]>;
  index?: number;
}) {
  const paid = section.status === "ok" ? section.data.filter((b) => b.status === "paid").length : 0;
  const shown = section.status === "ok" ? section.data.length : 0;

  return (
    <GlassCard variant="dark" index={index} testId="card-recent-bookings">
      <CardHeader
        label="Recent Bookings"
        icon={Receipt}
        trailing={
          shown > 0 ? (
            <span
              data-testid="paid-counter"
              className="rounded-full bg-white/15 px-2.5 py-1 text-xs font-semibold text-white tabular-nums"
            >
              {paid}/{shown} paid
            </span>
          ) : undefined
        }
      />
      {section.status === "error" ? (
        <CardError label="Couldn't load recent bookings" />
      ) : section.data.length === 0 ? (
        <CardEmpty message="No bookings yet" hint="The latest bookings will be listed here." />
      ) : (
        <ul className="flex flex-col divide-y divide-white/10">
          {section.data.map((booking) => (
            <li key={booking.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-white">{booking.tripName}</p>
                <p className="text-xs text-white/70">
                  <span className="capitalize">{booking.bookingType}</span> · {vietnamDayShort(booking.createdAt)}
                </p>
              </div>
              <div className="flex shrink-0 flex-col items-end gap-1">
                <span className="text-sm font-medium text-white tabular-nums">
                  {booking.amountVnd === null ? "—" : formatCompactVnd(booking.amountVnd)}
                </span>
                <span
                  className={cn(
                    "rounded-full px-2 py-0.5 text-[11px] font-semibold",
                    STATUS_CLASS[booking.status] ?? "bg-white/15 text-white/90",
                  )}
                >
                  {STATUS_LABEL[booking.status] ?? booking.status}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </GlassCard>
  );
}

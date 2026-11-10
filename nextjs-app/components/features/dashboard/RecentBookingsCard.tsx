import { Receipt } from "lucide-react";
import type { RecentBookingItem } from "@/lib/server/admin-dashboard";
import { formatCompactVnd } from "@/lib/format/vnd";
import { cn } from "@/lib/utils";
import { CardHeader } from "./primitives/CardHeader";
import { GlassCard } from "./primitives/GlassCard";
import { TaskList } from "./primitives/TaskList";

const STATUS_LABEL: Record<string, string> = { to_book: "To Book", booked: "Booked", paid: "Paid" };
const STATUS_CLASS: Record<string, string> = { to_book: "text-ink/50", booked: "text-warn", paid: "text-success" };

export function RecentBookingsCard({ bookings }: { bookings: RecentBookingItem[] }) {
  return (
    <GlassCard>
      <CardHeader label="Recent Bookings" icon={Receipt} />
      <TaskList
        emptyLabel="No bookings yet"
        items={bookings.map((booking) => ({
          id: booking.id,
          title: booking.tripName,
          // Trip name/type/amount/status only — never the booking creator's email/phone.
          meta: `${booking.bookingType} booking`,
          trailing: (
            <div className="flex flex-col items-end gap-0.5">
              <span className="text-ink font-medium">
                {booking.amountVnd === null ? "—" : `${formatCompactVnd(booking.amountVnd)} ₫`}
              </span>
              <span className={cn("text-xs font-medium", STATUS_CLASS[booking.status])}>
                {STATUS_LABEL[booking.status] ?? booking.status}
              </span>
            </div>
          ),
        }))}
      />
    </GlassCard>
  );
}

import type { BookingMixEntry } from "./types";

/**
 * `TripBooking.bookingType` is a free-form string, not an enum. These four are
 * the types the app writes today; the Booking Mix card always shows all four
 * (zero-filled) so the rows don't jump around, and appends any other value it
 * finds in the data after them, most frequent first.
 */
export const BOOKING_TYPES = ["flight", "stay", "activity", "transport"] as const;

export function fillBookingMix(rows: BookingMixEntry[]): BookingMixEntry[] {
  const byType = new Map(rows.map((row) => [row.bookingType, row]));

  const canonical = BOOKING_TYPES.map(
    (type): BookingMixEntry =>
      byType.get(type) ?? { bookingType: type, count: 0, amountVnd: 0 },
  );
  const extras = rows
    .filter(
      (row) => !(BOOKING_TYPES as readonly string[]).includes(row.bookingType),
    )
    .sort(
      (a, b) =>
        b.count - a.count || a.bookingType.localeCompare(b.bookingType),
    );

  return [...canonical, ...extras];
}

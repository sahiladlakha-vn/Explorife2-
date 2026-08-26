import '../../models/trip_booking.dart';

// ─────────────────────────────────────────
// BOOKINGS ON THE ITINERARY — derived display only. A booking never becomes
// a TripStop; every render just asks "which bookings fall on this day, and
// where" from trip_bookings, so there's exactly one source of truth (matches
// the existing stopId-pin relationship's own philosophy, just keyed by date
// instead of an explicit link).
//
// Pure logic, no Flutter/provider imports — extracted out of
// profile/tabs/trips_tab.dart (a `part of` file, where these were previously
// private and untestable from outside that library) so it can be unit
// tested directly. Mirrors the trip_insights.dart split: UI stays UI, the
// day/slot math it depends on lives here.
// ─────────────────────────────────────────

/// 1-based day index a [date] falls on relative to [tripStart] — the same
/// indexing TripStop.day already uses (day 1 == tripStart). Date-only: the
/// time-of-day component never shifts which day a booking is "on".
int dayIndexFor(DateTime date, DateTime tripStart) {
  final d = DateTime(date.year, date.month, date.day);
  final s = DateTime(tripStart.year, tripStart.month, tripStart.day);
  return d.difference(s).inDays + 1;
}

/// Slot bucket for a single moment, by hour: <12 morning, 12–18 afternoon,
/// >=18 evening — same boundaries the Itinerary's own display-time fallback
/// uses (08:30/12:00/18:00). Exact midnight means the booking form's
/// date+time picker was skipped (no real time given), which would otherwise
/// misbucket into "morning" — so it falls back to a type/moment-appropriate
/// guess instead: check-in defaults to afternoon (typical hotel check-in), a
/// check-out defaults to morning (typical check-out), everything else to
/// afternoon.
String slotForBookingMoment(DateTime dt, {required bool isCheckout}) {
  final noTimeGiven = dt.hour == 0 && dt.minute == 0;
  if (noTimeGiven) return isCheckout ? 'morning' : 'afternoon';
  if (dt.hour < 12) return 'morning';
  if (dt.hour < 18) return 'afternoon';
  return 'evening';
}

/// One booking rendered as a compact, non-draggable chip in a specific slot —
/// [label] carries the check-in/check-out framing for Stay bookings; other
/// types just show the booking's own title.
class BookingChipData {
  final TripBooking booking;
  final String label;
  const BookingChipData({required this.booking, required this.label});

  @override
  bool operator ==(Object other) =>
      other is BookingChipData &&
      other.booking.id == booking.id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(booking.id, label);
}

typedef DayBookings = ({
  Map<String, List<BookingChipData>> chips,
  List<TripBooking> stayBanners,
});

/// Buckets every booking relevant to [day] into its slot chip (Flight/
/// Activity/Transport, and Stay's check-in/check-out endpoints) or a
/// stay-banner (a Stay booking whose range spans THROUGH [day] — strictly
/// between check-in and check-out, not on either endpoint day). A Stay with
/// no [TripBooking.endAt] only ever gets a check-in chip; same-day check-in/
/// check-out collapses to one chip, not two.
DayBookings bookingsForDay(
    List<TripBooking> bookings, int day, DateTime tripStart) {
  final chips = <String, List<BookingChipData>>{
    'morning': [],
    'afternoon': [],
    'evening': [],
  };
  final banners = <TripBooking>[];

  for (final b in bookings) {
    if (b.bookingType == BookingType.stay) {
      final ciDay =
          b.startAt != null ? dayIndexFor(b.startAt!, tripStart) : null;
      if (ciDay == null) continue; // no check-in date — nothing to place
      final coDay = b.endAt != null ? dayIndexFor(b.endAt!, tripStart) : null;

      if (coDay == null || coDay == ciDay) {
        // No checkout, or a same-day stay — one chip on the check-in day.
        if (ciDay == day) {
          chips[slotForBookingMoment(b.startAt!, isCheckout: false)]!.add(
              BookingChipData(
                  booking: b,
                  label: coDay == null ? 'Check in: ${b.title}' : b.title));
        }
        continue;
      }

      if (day == ciDay) {
        chips[slotForBookingMoment(b.startAt!, isCheckout: false)]!.add(
            BookingChipData(booking: b, label: 'Check in: ${b.title}'));
      } else if (day == coDay) {
        chips[slotForBookingMoment(b.endAt!, isCheckout: true)]!.add(
            BookingChipData(booking: b, label: 'Check out: ${b.title}'));
      } else if (day > ciDay && day < coDay) {
        banners.add(b);
      }
    } else {
      // Flight / Activity / Transport — a single point in time.
      if (b.startAt == null) continue; // no date — nothing to place
      if (dayIndexFor(b.startAt!, tripStart) == day) {
        chips[slotForBookingMoment(b.startAt!, isCheckout: false)]!
            .add(BookingChipData(booking: b, label: b.title));
      }
    }
  }

  return (chips: chips, stayBanners: banners);
}

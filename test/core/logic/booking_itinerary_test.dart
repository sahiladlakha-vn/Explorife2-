// Regression tests for the Bookings-on-the-Itinerary derivation logic
// (extracted from profile/tabs/trips_tab.dart into a standalone, testable
// file this session). Covers: day-index math, slot bucketing (including the
// "no time given" midnight special case), and how a booking's date range
// buckets into per-day chips vs. multi-night stay banners.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/logic/booking_itinerary.dart';
import 'package:explorife/models/trip_booking.dart';

TripBooking _booking({
  String id = 'b1',
  BookingType type = BookingType.activity,
  String title = 'Test booking',
  DateTime? startAt,
  DateTime? endAt,
}) =>
    TripBooking(
      id: id,
      tripId: 'trip1',
      bookingType: type,
      title: title,
      startAt: startAt,
      endAt: endAt,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final tripStart = DateTime(2026, 8, 14); // Day 1

  group('dayIndexFor', () {
    test('trip start date is day 1', () {
      expect(dayIndexFor(DateTime(2026, 8, 14), tripStart), 1);
    });

    test('the next date is day 2', () {
      expect(dayIndexFor(DateTime(2026, 8, 15), tripStart), 2);
    });

    test('a date before trip start is day 0 or negative', () {
      expect(dayIndexFor(DateTime(2026, 8, 13), tripStart), 0);
    });

    test('time-of-day never shifts the day — only the date matters', () {
      final earlyMorning = DateTime(2026, 8, 15, 0, 30);
      final lateNight = DateTime(2026, 8, 15, 23, 59);
      expect(dayIndexFor(earlyMorning, tripStart), 2);
      expect(dayIndexFor(lateNight, tripStart), 2);
    });
  });

  group('slotForBookingMoment', () {
    test('before noon is morning', () {
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15, 9, 0), isCheckout: false),
          'morning');
    });

    test('noon up to 6pm is afternoon', () {
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15, 12, 0), isCheckout: false),
          'afternoon');
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15, 17, 59), isCheckout: false),
          'afternoon');
    });

    test('6pm or later is evening', () {
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15, 18, 0), isCheckout: false),
          'evening');
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15, 23, 0), isCheckout: false),
          'evening');
    });

    test('exact midnight (no time given) defaults to afternoon for check-in/'
        'non-checkout moments', () {
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15), isCheckout: false),
          'afternoon');
    });

    test('exact midnight (no time given) defaults to morning for checkout '
        'moments', () {
      expect(
          slotForBookingMoment(DateTime(2026, 8, 15), isCheckout: true),
          'morning');
    });
  });

  group('bookingsForDay — Flight/Activity/Transport (single point in time)', () {
    test('places a chip on the day the booking falls on', () {
      final b = _booking(
          type: BookingType.flight,
          title: 'VN203',
          startAt: DateTime(2026, 8, 15, 8, 0));
      final result = bookingsForDay([b], 2, tripStart);
      expect(result.chips['morning'], hasLength(1));
      expect(result.chips['morning']!.first.label, 'VN203');
      expect(result.chips['afternoon'], isEmpty);
      expect(result.stayBanners, isEmpty);
    });

    test('does not place a chip on a different day', () {
      final b = _booking(
          type: BookingType.activity, startAt: DateTime(2026, 8, 15, 8, 0));
      final result = bookingsForDay([b], 1, tripStart);
      expect(result.chips.values.every((v) => v.isEmpty), isTrue);
    });

    test('a booking with no startAt is skipped entirely', () {
      final b = _booking(type: BookingType.activity, startAt: null);
      final result = bookingsForDay([b], 1, tripStart);
      expect(result.chips.values.every((v) => v.isEmpty), isTrue);
      expect(result.stayBanners, isEmpty);
    });

    test('transport bucketed the same way as activity/flight', () {
      final b = _booking(
          type: BookingType.transport, startAt: DateTime(2026, 8, 14, 19, 0));
      final result = bookingsForDay([b], 1, tripStart);
      expect(result.chips['evening'], hasLength(1));
    });
  });

  group('bookingsForDay — Stay, no checkout date', () {
    test('one "Check in:" chip on the check-in day only', () {
      final b = _booking(
          type: BookingType.stay,
          title: 'Hanoi Hilton',
          startAt: DateTime(2026, 8, 15));
      final onCheckInDay = bookingsForDay([b], 2, tripStart);
      final chips = onCheckInDay.chips.values.expand((v) => v).toList();
      expect(chips, hasLength(1));
      expect(chips.first.label, 'Check in: Hanoi Hilton');
      expect(onCheckInDay.stayBanners, isEmpty);

      final onOtherDay = bookingsForDay([b], 3, tripStart);
      expect(onOtherDay.chips.values.every((v) => v.isEmpty), isTrue);
      expect(onOtherDay.stayBanners, isEmpty);
    });
  });

  group('bookingsForDay — Stay, same-day check-in/check-out', () {
    test('collapses to one chip with the plain title, not "Check in:"', () {
      final b = _booking(
          type: BookingType.stay,
          title: 'Day-use spa',
          startAt: DateTime(2026, 8, 15, 10, 0),
          endAt: DateTime(2026, 8, 15, 18, 0));
      final result = bookingsForDay([b], 2, tripStart);
      final chips = result.chips.values.expand((v) => v).toList();
      expect(chips, hasLength(1));
      expect(chips.first.label, 'Day-use spa');
      expect(result.stayBanners, isEmpty);
    });
  });

  group('bookingsForDay — Stay, one-night (adjacent days)', () {
    final b = _booking(
        type: BookingType.stay,
        title: 'Riverside Inn',
        startAt: DateTime(2026, 8, 14),
        endAt: DateTime(2026, 8, 15));

    test('check-in chip on day 1, no banner day in between', () {
      final day1 = bookingsForDay([b], 1, tripStart);
      final chips1 = day1.chips.values.expand((v) => v).toList();
      expect(chips1, hasLength(1));
      expect(chips1.first.label, 'Check in: Riverside Inn');
      expect(day1.stayBanners, isEmpty);
    });

    test('check-out chip on day 2', () {
      final day2 = bookingsForDay([b], 2, tripStart);
      final chips2 = day2.chips.values.expand((v) => v).toList();
      expect(chips2, hasLength(1));
      expect(chips2.first.label, 'Check out: Riverside Inn');
      expect(day2.stayBanners, isEmpty);
    });
  });

  group('bookingsForDay — Stay, multi-night', () {
    // Aug 14 (day1) check-in, Aug 17 (day4) check-out — 2 nights strictly
    // in between (day2, day3) should get a banner, not a chip.
    final b = _booking(
        type: BookingType.stay,
        title: 'Beach Resort',
        startAt: DateTime(2026, 8, 14, 15, 0), // 3pm check-in -> afternoon
        endAt: DateTime(2026, 8, 17, 11, 0)); // 11am check-out -> morning

    test('check-in day gets a chip in the check-in\'s own slot, no banner', () {
      final day1 = bookingsForDay([b], 1, tripStart);
      expect(day1.chips['afternoon'], hasLength(1));
      expect(day1.chips['afternoon']!.first.label, 'Check in: Beach Resort');
      expect(day1.stayBanners, isEmpty);
    });

    test('nights strictly in between get a banner, not a slot chip', () {
      final day2 = bookingsForDay([b], 2, tripStart);
      expect(day2.chips.values.every((v) => v.isEmpty), isTrue);
      expect(day2.stayBanners, hasLength(1));
      expect(day2.stayBanners.first.id, b.id);

      final day3 = bookingsForDay([b], 3, tripStart);
      expect(day3.chips.values.every((v) => v.isEmpty), isTrue);
      expect(day3.stayBanners, hasLength(1));
    });

    test('check-out day gets a chip in the check-out\'s own slot, no banner', () {
      final day4 = bookingsForDay([b], 4, tripStart);
      expect(day4.chips['morning'], hasLength(1));
      expect(day4.chips['morning']!.first.label, 'Check out: Beach Resort');
      expect(day4.stayBanners, isEmpty);
    });
  });

  group('bookingsForDay — multiple bookings on the same day', () {
    test('each lands in its own slot independently', () {
      final flight = _booking(
          id: 'f1',
          type: BookingType.flight,
          title: 'Morning flight',
          startAt: DateTime(2026, 8, 14, 6, 0));
      final activity = _booking(
          id: 'a1',
          type: BookingType.activity,
          title: 'Evening tour',
          startAt: DateTime(2026, 8, 14, 19, 0));
      final result = bookingsForDay([flight, activity], 1, tripStart);
      expect(result.chips['morning'], hasLength(1));
      expect(result.chips['evening'], hasLength(1));
      expect(result.chips['afternoon'], isEmpty);
    });
  });
}

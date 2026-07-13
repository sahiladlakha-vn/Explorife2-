// Pure unit tests for trip_insights — no Supabase / network / widget deps, so
// they run fast and deterministically. `now` is always injected. Focus is
// computePace's cumulative-actual composition (the dedup + day-attribution
// rules) plus the null-vs-0 money contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/logic/trip_insights.dart';
import 'package:explorife/models/trip_stop.dart';
import 'package:explorife/models/trip_booking.dart';

TripStop _stop({
  required String id,
  required int day,
  int priceVnd = 0,
  String slot = 'morning',
}) =>
    TripStop(
      id: id,
      tripId: 't1',
      day: day,
      slot: slot,
      priceVnd: priceVnd,
    );

TripBooking _booking({
  required String id,
  String? stopId,
  BookingType type = BookingType.activity,
  int? amountVnd,
  BookingStatus status = BookingStatus.booked,
  DateTime? startAt,
}) =>
    TripBooking(
      id: id,
      tripId: 't1',
      stopId: stopId,
      bookingType: type,
      title: id,
      amountVnd: amountVnd,
      status: status,
      startAt: startAt,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  // Trip: day 1 == 2026-07-13; "now" sits on day 3.
  final tripStart = DateTime(2026, 7, 13);
  final now = DateTime(2026, 7, 15, 12); // day 3

  group('computePace cumulative actual', () {
    test('NAMED: committed pinned booking supersedes the stop estimate '
        '(no double count)', () {
      // A paid booking pinned to a stop must REPLACE that stop's priceVnd, not
      // stack on top of it. Stop = 500k, booking = 600k → actual is 600k.
      final stops = [_stop(id: 's1', day: 1, priceVnd: 500000)];
      final bookings = [
        _booking(
          id: 'b1',
          stopId: 's1',
          amountVnd: 600000,
          status: BookingStatus.paid,
          startAt: tripStart,
        ),
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: stops,
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      expect(pace.cumulativeActual, 600000);
    });

    test('future booked leg still supersedes its stop estimate but is not '
        'counted itself', () {
      // Rule 1 drops the stop estimate even when Rule 3 excludes the booking
      // (booked + startAt in the future) → that stop contributes 0.
      final stops = [_stop(id: 's1', day: 1, priceVnd: 500000)];
      final bookings = [
        _booking(
          id: 'b1',
          stopId: 's1',
          amountVnd: 600000,
          status: BookingStatus.booked,
          startAt: now.add(const Duration(days: 1)),
        ),
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: stops,
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      expect(pace.cumulativeActual, 0);
    });

    test('stops only cumulate up to today', () {
      final stops = [
        _stop(id: 's1', day: 1, priceVnd: 100000),
        _stop(id: 's3', day: 3, priceVnd: 200000),
        _stop(id: 's5', day: 5, priceVnd: 400000), // future, excluded
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: stops,
        bookings: const [],
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      expect(pace.cumulativeActual, 300000);
    });

    test('paid counts regardless of date; to_book never counts', () {
      final bookings = [
        _booking(
          id: 'paidFuture',
          amountVnd: 100000,
          status: BookingStatus.paid,
          startAt: now.add(const Duration(days: 2)),
        ),
        _booking(
          id: 'toBookKnown',
          amountVnd: 999000,
          status: BookingStatus.toBook,
          startAt: tripStart,
        ),
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: const [],
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      expect(pace.cumulativeActual, 100000);
    });

    test('booked counts only when startAt <= now; null startAt excluded', () {
      final bookings = [
        _booking(
          id: 'past',
          amountVnd: 100000,
          status: BookingStatus.booked,
          startAt: tripStart,
        ),
        _booking(
          id: 'future',
          amountVnd: 200000,
          status: BookingStatus.booked,
          startAt: now.add(const Duration(days: 1)),
        ),
        _booking(
          id: 'undated',
          amountVnd: 400000,
          status: BookingStatus.booked,
          startAt: null,
        ),
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: const [],
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      expect(pace.cumulativeActual, 100000);
    });

    test('null amount is TBD and excluded; 0 is free and counts', () {
      final bookings = [
        _booking(
          id: 'tbd',
          amountVnd: null,
          status: BookingStatus.paid,
          startAt: tripStart,
        ),
        _booking(
          id: 'free',
          amountVnd: 0,
          status: BookingStatus.paid,
          startAt: tripStart,
        ),
      ];

      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: const [],
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );

      // Both contribute 0 to the sum, but for opposite reasons — the important
      // thing is no crash and no phantom spend from the TBD row.
      expect(pace.cumulativeActual, 0);
    });
  });

  group('computePace status', () {
    test('notStarted before the trip begins', () {
      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: const [],
        bookings: const [],
        tripStart: tripStart,
        tripDays: 5,
        now: tripStart.subtract(const Duration(days: 1)),
      );
      expect(pace.status, PaceStatus.notStarted);
      expect(pace.tripDayToday, 0);
    });

    test('noBudget when total budget is 0', () {
      final pace = computePace(
        totalBudgetVnd: 0,
        stops: const [],
        bookings: const [],
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );
      expect(pace.status, PaceStatus.noBudget);
    });

    test('overPace when actual is well beyond the straight-line expectation',
        () {
      // Day 3 of 5, budget 5M → expected ~3M. Spend 5M → overPace.
      final bookings = [
        _booking(
          id: 'big',
          amountVnd: 5000000,
          status: BookingStatus.paid,
          startAt: tripStart,
        ),
      ];
      final pace = computePace(
        totalBudgetVnd: 5000000,
        stops: const [],
        bookings: bookings,
        tripStart: tripStart,
        tripDays: 5,
        now: now,
      );
      expect(pace.status, PaceStatus.overPace);
      expect(pace.delta, greaterThan(0));
    });
  });

  group('alerts', () {
    test('unbookedStopAlerts flags only stops with no pinned booking', () {
      final stops = [
        _stop(id: 's1', day: 1, priceVnd: 100000),
        _stop(id: 's2', day: 2, priceVnd: 200000),
      ];
      final bookings = [_booking(id: 'b1', stopId: 's1', amountVnd: 100000)];

      final alerts =
          unbookedStopAlerts(tripId: 't1', stops: stops, bookings: bookings);

      expect(alerts.length, 1);
      expect(alerts.single.stopId, 's2');
      expect(alerts.single.kind, AlertKind.unbookedStop);
    });

    test('overBudgetCategoryAlerts fires only over a positive plan', () {
      final alerts = overBudgetCategoryAlerts(
        tripId: 't1',
        plannedByCategory: {'food': 100000, 'stay': 0},
        actualByCategory: {'food': 160000, 'stay': 500000},
      );
      expect(alerts.length, 1);
      expect(alerts.single.category, 'food');
      expect(alerts.single.payload['overVnd'], 60000);
      // 60% over → critical.
      expect(alerts.single.severity, AlertSeverity.critical);
    });

    test('upcomingBookingAlerts marks imminent to_book as critical', () {
      final bookings = [
        _booking(
          id: 'soon',
          status: BookingStatus.toBook,
          startAt: now.add(const Duration(days: 1)),
        ),
        _booking(
          id: 'far',
          status: BookingStatus.toBook,
          startAt: now.add(const Duration(days: 30)),
        ),
      ];
      final alerts = upcomingBookingAlerts(
        tripId: 't1',
        bookings: bookings,
        now: now,
      );
      expect(alerts.length, 1);
      expect(alerts.single.bookingId, 'soon');
      expect(alerts.single.severity, AlertSeverity.critical);
    });

    test('tripAlerts sorts most-urgent first', () {
      final stops = [_stop(id: 's2', day: 2)]; // → info unbooked alert
      final bookings = [
        _booking(
          id: 'soon',
          status: BookingStatus.toBook,
          startAt: now.add(const Duration(days: 1)),
        ), // → critical
      ];
      final alerts = tripAlerts(
        tripId: 't1',
        stops: stops,
        bookings: bookings,
        plannedByCategory: const {},
        actualByCategory: const {},
        now: now,
      );
      expect(alerts.first.severity, AlertSeverity.critical);
    });
  });

  group('evaluateBadges', () {
    test('earned when count reaches threshold, clamped progress otherwise', () {
      final progress = evaluateBadges(counts: {
        BadgeMetric.gems: 10,
        BadgeMetric.trips: 0,
      });

      final collector = progress.firstWhere((p) => p.def.id == 'gem_collector');
      expect(collector.earned, isTrue);
      expect(collector.progress, 1.0);

      final firstTrip = progress.firstWhere((p) => p.def.id == 'first_trip');
      expect(firstTrip.earned, isFalse);
      expect(firstTrip.progress, 0.0);

      final curator = progress.firstWhere((p) => p.def.id == 'gem_curator');
      expect(curator.earned, isFalse);
      expect(curator.progress, closeTo(10 / 50, 1e-9));
    });

    test('missing metric counts as zero', () {
      final progress = evaluateBadges(counts: const {});
      expect(progress.every((p) => p.current == 0), isTrue);
      expect(progress.any((p) => p.earned), isFalse);
    });
  });

  group('spend composition (shared dedup + whole-trip actuals)', () {
    // Buckets a stop by a caller-side id→category map (stands in for the
    // provider's gem-catalogue bucketer). Unknown ids fall to 'activity'.
    String Function(TripStop) bucketer(Map<String, String> byId) =>
        (s) => byId[s.id] ?? 'activity';

    test('supersededStopIds: only committed pinned bookings supersede', () {
      final bookings = [
        _booking(id: 'paidPinned', stopId: 's1', status: BookingStatus.paid),
        _booking(
            id: 'bookedPinned', stopId: 's2', status: BookingStatus.booked),
        _booking(
            id: 'toBookPinned', stopId: 's3', status: BookingStatus.toBook),
        _booking(id: 'unpinned', status: BookingStatus.paid),
      ];
      // to_book doesn't commit; an unpinned booking has no stop to supersede.
      expect(supersededStopIds(bookings), {'s1', 's2'});
    });

    test('bookingCategory: flights + transport roll up to transit', () {
      expect(
          bookingCategory(_booking(id: 'a', type: BookingType.stay)), 'stay');
      expect(bookingCategory(_booking(id: 'b', type: BookingType.activity)),
          'activity');
      expect(bookingCategory(_booking(id: 'c', type: BookingType.flight)),
          'transit');
      expect(bookingCategory(_booking(id: 'd', type: BookingType.transport)),
          'transit');
    });

    test('dedup moves money to the booking category, dropping the stop', () {
      // Stop is a 'stay' estimate; a paid ACTIVITY booking pinned to it wins:
      // the stay estimate drops out, 600k lands in activity instead.
      final stops = [_stop(id: 's1', day: 1, priceVnd: 500000)];
      final bookings = [
        _booking(
          id: 'b1',
          stopId: 's1',
          type: BookingType.activity,
          amountVnd: 600000,
          status: BookingStatus.paid,
        ),
      ];
      final actual = actualSpendByCategory(
        stops: stops,
        bookings: bookings,
        stopCategory: bucketer({'s1': 'stay'}),
      );
      expect(actual['activity'], 600000);
      expect(actual['stay'], isNull); // superseded → no stay spend
    });

    test('future booked leg counts (whole-trip lens differs from pace)', () {
      final bookings = [
        _booking(
          id: 'b1',
          type: BookingType.stay,
          amountVnd: 300000,
          status: BookingStatus.booked,
          startAt: now.add(const Duration(days: 5)),
        ),
      ];
      final actual = actualSpendByCategory(
        stops: const [],
        bookings: bookings,
        stopCategory: bucketer(const {}),
      );
      // computePace would EXCLUDE this future booked leg; the envelope counts it.
      expect(actual['stay'], 300000);
    });

    test('to_book excluded, null amount excluded, 0 counts', () {
      final bookings = [
        _booking(
          id: 'toBook',
          type: BookingType.activity,
          amountVnd: 999000,
          status: BookingStatus.toBook,
        ),
        _booking(
          id: 'tbd',
          type: BookingType.activity,
          amountVnd: null,
          status: BookingStatus.paid,
        ),
        _booking(
          id: 'free',
          type: BookingType.activity,
          amountVnd: 0,
          status: BookingStatus.paid,
        ),
      ];
      final actual = actualSpendByCategory(
        stops: const [],
        bookings: bookings,
        stopCategory: bucketer(const {}),
      );
      // Only the free (0) row lands; to_book and the TBD null contribute nothing.
      expect(actual['activity'], 0);
    });

    test('flights and transport aggregate into transit', () {
      final bookings = [
        _booking(
          id: 'flight',
          type: BookingType.flight,
          amountVnd: 100000,
          status: BookingStatus.paid,
        ),
        _booking(
          id: 'taxi',
          type: BookingType.transport,
          amountVnd: 200000,
          status: BookingStatus.paid,
        ),
      ];
      final actual = actualSpendByCategory(
        stops: const [],
        bookings: bookings,
        stopCategory: bucketer(const {}),
      );
      expect(actual['transit'], 300000);
    });
  });
}

// Regression tests for TripBooking — in particular the sentinel-based
// copyWith fixed this session (previously only amountVnd could be cleared
// back to null; stopId/confirmationRef/provider/startAt/endAt silently could
// not be, which is exactly the kind of bug that creeps back in unnoticed).

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/trip_booking.dart';

TripBooking _full() => TripBooking(
      id: 'bk1',
      tripId: 'trip1',
      stopId: 'stop1',
      bookingType: BookingType.stay,
      title: 'Hanoi Hilton',
      confirmationRef: 'CONF123',
      provider: 'Hilton',
      startAt: DateTime.utc(2026, 8, 14, 14, 0),
      endAt: DateTime.utc(2026, 8, 16, 11, 0),
      amountVnd: 1500000,
      status: BookingStatus.booked,
      createdBy: 'user1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('BookingType', () {
    test('wire matches the enum name for every value (DB CHECK constraint)', () {
      expect(BookingType.flight.wire, 'flight');
      expect(BookingType.stay.wire, 'stay');
      expect(BookingType.activity.wire, 'activity');
      expect(BookingType.transport.wire, 'transport');
    });

    test('fromWire round-trips every known value', () {
      for (final t in BookingType.values) {
        expect(BookingType.fromWire(t.wire), t);
      }
    });

    test('fromWire falls back to activity for an unknown/null value', () {
      expect(BookingType.fromWire('train'), BookingType.activity);
      expect(BookingType.fromWire(null), BookingType.activity);
    });
  });

  group('BookingStatus', () {
    test('wire uses snake_case, distinct from the camelCase enum name', () {
      expect(BookingStatus.toBook.wire, 'to_book');
      expect(BookingStatus.booked.wire, 'booked');
      expect(BookingStatus.paid.wire, 'paid');
    });

    test('fromWire round-trips every known value', () {
      for (final s in BookingStatus.values) {
        expect(BookingStatus.fromWire(s.wire), s);
      }
    });

    test('fromWire falls back to toBook for an unknown/null value '
        '(matches the column default)', () {
      expect(BookingStatus.fromWire('cancelled'), BookingStatus.toBook);
      expect(BookingStatus.fromWire(null), BookingStatus.toBook);
    });
  });

  group('hasKnownAmount — MONEY CONTRACT', () {
    test('null amount is unknown (TBD)', () {
      expect(_full().copyWith(amountVnd: null).hasKnownAmount, isFalse);
    });

    test('zero amount is a known, confirmed-free amount', () {
      expect(_full().copyWith(amountVnd: 0).hasKnownAmount, isTrue);
    });

    test('a positive amount is known', () {
      expect(_full().hasKnownAmount, isTrue);
    });
  });

  group('fromJson / toJson round trip', () {
    test('every field survives a round trip', () {
      final original = _full();
      final restored = TripBooking.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.tripId, original.tripId);
      expect(restored.stopId, original.stopId);
      expect(restored.bookingType, original.bookingType);
      expect(restored.title, original.title);
      expect(restored.confirmationRef, original.confirmationRef);
      expect(restored.provider, original.provider);
      expect(restored.startAt!.toUtc(), original.startAt!.toUtc());
      expect(restored.endAt!.toUtc(), original.endAt!.toUtc());
      expect(restored.amountVnd, original.amountVnd);
      expect(restored.status, original.status);
      expect(restored.createdBy, original.createdBy);
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
    });

    test('nullable fields round-trip as null (a trip-level booking with no '
        'stop, no confirmation, no dates, no amount)', () {
      final bare = TripBooking(
        id: 'bk2',
        tripId: 'trip1',
        bookingType: BookingType.activity,
        title: 'Something TBD',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final restored = TripBooking.fromJson(bare.toJson());
      expect(restored.stopId, isNull);
      expect(restored.confirmationRef, isNull);
      expect(restored.provider, isNull);
      expect(restored.startAt, isNull);
      expect(restored.endAt, isNull);
      expect(restored.amountVnd, isNull);
      expect(restored.hasKnownAmount, isFalse);
      expect(restored.status, BookingStatus.toBook); // column default
    });

    test('amountVnd of exactly 0 (confirmed free) round-trips as 0, not null',
        () {
      final free = _full().copyWith(amountVnd: 0);
      final restored = TripBooking.fromJson(free.toJson());
      expect(restored.amountVnd, 0);
      expect(restored.hasKnownAmount, isTrue);
    });
  });

  group('copyWith — sentinel-based clear vs. preserve (the actual bug fix)', () {
    test('omitting every arg preserves all current values unchanged', () {
      final original = _full();
      final copy = original.copyWith();
      expect(copy.stopId, original.stopId);
      expect(copy.confirmationRef, original.confirmationRef);
      expect(copy.provider, original.provider);
      expect(copy.startAt, original.startAt);
      expect(copy.endAt, original.endAt);
      expect(copy.amountVnd, original.amountVnd);
      expect(copy.title, original.title);
      expect(copy.bookingType, original.bookingType);
      expect(copy.status, original.status);
    });

    test('passing explicit null CLEARS stopId (unpin from a stop)', () {
      final cleared = _full().copyWith(stopId: null);
      expect(cleared.stopId, isNull);
    });

    test('passing explicit null CLEARS confirmationRef', () {
      final cleared = _full().copyWith(confirmationRef: null);
      expect(cleared.confirmationRef, isNull);
    });

    test('passing explicit null CLEARS provider', () {
      final cleared = _full().copyWith(provider: null);
      expect(cleared.provider, isNull);
    });

    test('passing explicit null CLEARS startAt', () {
      final cleared = _full().copyWith(startAt: null);
      expect(cleared.startAt, isNull);
    });

    test('passing explicit null CLEARS endAt', () {
      final cleared = _full().copyWith(endAt: null);
      expect(cleared.endAt, isNull);
    });

    test('passing explicit null CLEARS amountVnd back to TBD', () {
      final cleared = _full().copyWith(amountVnd: null);
      expect(cleared.amountVnd, isNull);
      expect(cleared.hasKnownAmount, isFalse);
    });

    test('passing a real value SETS the field, independent of clearing '
        'other fields in the same call', () {
      final updated = _full().copyWith(
        stopId: null, // clear
        provider: 'Marriott', // set
        // confirmationRef, startAt, endAt, amountVnd all omitted -> preserved
      );
      expect(updated.stopId, isNull);
      expect(updated.provider, 'Marriott');
      expect(updated.confirmationRef, _full().confirmationRef);
      expect(updated.startAt, _full().startAt);
      expect(updated.endAt, _full().endAt);
      expect(updated.amountVnd, _full().amountVnd);
    });

    test('title, bookingType, and status update via plain replacement', () {
      final updated = _full().copyWith(
        title: 'Renamed',
        bookingType: BookingType.flight,
        status: BookingStatus.paid,
      );
      expect(updated.title, 'Renamed');
      expect(updated.bookingType, BookingType.flight);
      expect(updated.status, BookingStatus.paid);
    });

    test('id, tripId, createdBy, createdAt are identity — never touched by '
        'copyWith', () {
      final original = _full();
      final copy = original.copyWith(title: 'Different title');
      expect(copy.id, original.id);
      expect(copy.tripId, original.tripId);
      expect(copy.createdBy, original.createdBy);
      expect(copy.createdAt, original.createdAt);
    });
  });
}

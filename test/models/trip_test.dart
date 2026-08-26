// Regression tests for the Trip model's currency-feature additions this
// session (currency, description) plus the pre-existing money/date
// formatters that the whole currency feature is built on top of.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/trip.dart';

Trip _trip({
  String? currency,
  String? description,
  double? locationLat,
  double? locationLng,
}) =>
    Trip(
      id: 't1',
      ownerId: 'u1',
      name: 'Phong Nha trip',
      location: 'Phong Nha',
      locationLat: locationLat,
      locationLng: locationLng,
      description: description,
      startDate: DateTime(2026, 8, 14),
      endDate: DateTime(2026, 8, 16),
      budgetVnd: 5000000,
      currency: currency ?? 'VND',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('currency', () {
    test('defaults to VND when not specified (pre-currency-feature trips)',
        () {
      final t = Trip(
        id: 't2',
        ownerId: 'u1',
        name: 'Old trip',
        location: 'Hanoi',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
        budgetVnd: 1000000,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(t.currency, 'VND');
    });

    test('fromJson falls back to VND when the column is missing/null', () {
      final json = _trip().toJson()..remove('currency');
      final t = Trip.fromJson(json);
      expect(t.currency, 'VND');
    });

    test('fromJson reads a real currency code straight through', () {
      final json = _trip(currency: 'EUR').toJson();
      final t = Trip.fromJson(json);
      expect(t.currency, 'EUR');
    });

    test('copyWith can change the currency (this session\'s bug fix — it '
        'used to have no currency param at all)', () {
      final t = _trip(currency: 'VND');
      final updated = t.copyWith(currency: 'JPY');
      expect(updated.currency, 'JPY');
    });

    test('copyWith preserves currency when omitted', () {
      final t = _trip(currency: 'THB');
      final updated = t.copyWith(name: 'Renamed');
      expect(updated.currency, 'THB');
    });
  });

  group('description', () {
    test('round-trips through toJson/fromJson', () {
      final t = _trip(description: 'A cave-diving trip');
      final restored = Trip.fromJson(t.toJson());
      expect(restored.description, 'A cave-diving trip');
    });

    test('is null when absent (pre-existing trips, or left blank)', () {
      final t = _trip();
      expect(t.description, isNull);
      final restored = Trip.fromJson(t.toJson());
      expect(restored.description, isNull);
    });

    test('copyWith sets a description when one is provided', () {
      final t = _trip();
      final updated = t.copyWith(description: 'New description');
      expect(updated.description, 'New description');
    });

    test('copyWith cannot clear description to null — by design (plain '
        '`?? this.field`, no sentinel); callers needing to clear it '
        'construct a new Trip directly instead', () {
      final t = _trip(description: 'Existing description');
      final attempted = t.copyWith(description: null);
      expect(attempted.description, 'Existing description');
    });
  });

  group('displayName', () {
    test('uses the real name when set', () {
      expect(_trip().displayName, 'Phong Nha trip');
    });

    test('falls back to "<location> escape" for an empty name '
        '(blueprint-seeded trips never renamed)', () {
      final t = Trip(
        id: 't3',
        ownerId: 'u1',
        name: '',
        location: 'Da Nang',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 2),
        budgetVnd: 0,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(t.displayName, 'Da Nang escape');
    });
  });

  group('nights', () {
    test('computes whole nights between start and end', () {
      expect(_trip().nights, 2); // Aug 14 -> Aug 16
    });
  });

  group('Trip.formatDateRange', () {
    test('same month collapses to "Mon D – D"', () {
      expect(Trip.formatDateRange(DateTime(2026, 7, 12), DateTime(2026, 7, 18)),
          'Jul 12 – 18');
    });

    test('cross-month shows both month abbreviations', () {
      expect(Trip.formatDateRange(DateTime(2026, 7, 28), DateTime(2026, 8, 3)),
          'Jul 28 – Aug 3');
    });

    test('cross-year shows both full years', () {
      expect(
          Trip.formatDateRange(DateTime(2026, 12, 28), DateTime(2027, 1, 3)),
          'Dec 28, 2026 – Jan 3, 2027');
    });
  });

  group('Trip.formatVnd', () {
    test('long form groups thousands with commas', () {
      expect(Trip.formatVnd(1200000), '1,200,000');
      expect(Trip.formatVnd(5000000), '5,000,000');
      expect(Trip.formatVnd(999), '999');
    });

    test('long form handles negative numbers', () {
      expect(Trip.formatVnd(-1200000), '-1,200,000');
    });

    test('never includes a currency glyph — callers own that', () {
      expect(Trip.formatVnd(1200000), isNot(contains('₫')));
      expect(Trip.formatVnd(1200000), isNot(contains('\$')));
    });

    group('short form', () {
      test('whole millions get a bare M suffix', () {
        expect(Trip.formatVnd(1000000, short: true), '1M');
        expect(Trip.formatVnd(5000000, short: true), '5M');
      });

      test('fractional millions keep one decimal', () {
        expect(Trip.formatVnd(1200000, short: true), '1.2M');
      });

      test('whole thousands get a bare K suffix', () {
        expect(Trip.formatVnd(50000, short: true), '50K');
      });

      test('fractional thousands keep one decimal', () {
        expect(Trip.formatVnd(1500, short: true), '1.5K');
      });

      test('under 1,000 is the bare number', () {
        expect(Trip.formatVnd(500, short: true), '500');
      });
    });
  });
}

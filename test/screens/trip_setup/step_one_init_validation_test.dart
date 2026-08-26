// Regression tests for StepOneInit.isValid — the wizard's Continue-button
// gate. Covers the required-Title rule added this session (previously title
// wasn't part of the draft/validation at all) alongside the pre-existing
// location/dates/budget/vibe checks, so a future edit can't silently drop
// one of these without a test failing.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/trip_vibe.dart';
import 'package:explorife/providers/trip_provider.dart';
import 'package:explorife/screens/trip_setup/step_one_init.dart';

TripDraft _validDraft() => TripDraft()
  ..title = 'Summer in Japan'
  ..location = 'Tokyo'
  ..dateStart = DateTime(2026, 8, 14)
  ..dateEnd = DateTime(2026, 8, 16)
  ..budgetVnd = 5000000
  ..vibe = TripVibe.values.first;

void main() {
  test('a fully-filled draft is valid', () {
    expect(StepOneInit.isValid(_validDraft()), isTrue);
  });

  group('title (required — this session\'s addition)', () {
    test('null title is invalid', () {
      final d = _validDraft()..title = null;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('empty title is invalid', () {
      final d = _validDraft()..title = '';
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('whitespace-only title is invalid (trimmed before checking)', () {
      final d = _validDraft()..title = '   ';
      expect(StepOneInit.isValid(d), isFalse);
    });
  });

  group('location', () {
    test('null location is invalid', () {
      final d = _validDraft()..location = null;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('whitespace-only location is invalid', () {
      final d = _validDraft()..location = '  ';
      expect(StepOneInit.isValid(d), isFalse);
    });
  });

  group('dates', () {
    test('missing start date is invalid', () {
      final d = _validDraft()..dateStart = null;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('missing end date is invalid', () {
      final d = _validDraft()..dateEnd = null;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('a zero-night span (end == start) is invalid', () {
      final d = _validDraft()
        ..dateStart = DateTime(2026, 8, 14)
        ..dateEnd = DateTime(2026, 8, 14);
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('an inverted span (end before start) is invalid', () {
      final d = _validDraft()
        ..dateStart = DateTime(2026, 8, 16)
        ..dateEnd = DateTime(2026, 8, 14);
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('a one-night span is valid', () {
      final d = _validDraft()
        ..dateStart = DateTime(2026, 8, 14)
        ..dateEnd = DateTime(2026, 8, 15);
      expect(StepOneInit.isValid(d), isTrue);
    });
  });

  group('budget', () {
    test('zero budget is invalid', () {
      final d = _validDraft()..budgetVnd = 0;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('negative budget is invalid', () {
      final d = _validDraft()..budgetVnd = -1;
      expect(StepOneInit.isValid(d), isFalse);
    });

    test('any positive budget is valid', () {
      final d = _validDraft()..budgetVnd = 1;
      expect(StepOneInit.isValid(d), isTrue);
    });
  });

  group('vibe', () {
    test('no vibe selected is invalid', () {
      final d = _validDraft()..vibe = null;
      expect(StepOneInit.isValid(d), isFalse);
    });
  });

  test('currency is NOT part of validation — it always has a default, so '
      'it can never block Continue', () {
    final d = _validDraft();
    // TripDraft.currency defaults to 'VND' and is never null, so there's no
    // "missing currency" state to guard against here.
    expect(d.currency, 'VND');
    expect(StepOneInit.isValid(d), isTrue);
  });
}

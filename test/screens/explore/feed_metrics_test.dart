// Pure unit tests for the discovery-feed metrics — the sheet's named snap
// points and the distance-pill label. No Flutter binding, widgets or network.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/screens/explore/feed_metrics.dart';

void main() {
  group('SheetSnap', () {
    test('landing detent is the content-hugging peek', () {
      expect(SheetSnap.landing, SheetSnap.peek);
    });

    test('peek and full are the tunable fallback constants', () {
      expect(SheetSnap.peek.size, 0.32);
      expect(SheetSnap.full.size, 0.90);
      expect(SheetSnap.peek.size, lessThan(SheetSnap.full.size));
    });

    test('peekFractionFor measures the header, not a hardcoded fraction', () {
      // 150px header on a 750px sheet hugs at exactly 0.2 — derived, and
      // distinct from the old magic 0.32 peek fraction.
      final f = SheetSnap.peekFractionFor(
        headerHeight: 150,
        availableHeight: 750,
      );
      expect(f, closeTo(0.2, 1e-9));
      expect(f, isNot(SheetSnap.peek.size));
    });

    test('peekFractionFor stays the smallest detent (clamped at the cap)', () {
      // A header taller than the cap would otherwise overshoot into list space.
      final f = SheetSnap.peekFractionFor(
          headerHeight: 400, availableHeight: 500);
      expect(f, lessThan(SheetSnap.full.size));
      expect(f, closeTo(0.53, 1e-9));
    });

    test('peekFractionFor falls back to the constant when height unknown', () {
      expect(
        SheetSnap.peekFractionFor(headerHeight: 150, availableHeight: 0),
        SheetSnap.peek.size,
      );
    });

    test('fullFractionFor caps the sheet top below the reserved chip band', () {
      // 130px reserved at the top on an 800px sheet → top stops at 130px, so
      // the sheet covers (800-130)/800 of the height.
      final f = SheetSnap.fullFractionFor(
          topReservedPx: 130, availableHeight: 800);
      expect(f, closeTo((800 - 130) / 800, 1e-9));
      expect(f, lessThan(SheetSnap.full.size));
    });

    test('fullFractionFor never exceeds the tunable full constant', () {
      // A tiny reservation can't push the sheet taller than the full cap.
      final f = SheetSnap.fullFractionFor(
          topReservedPx: 1, availableHeight: 800);
      expect(f, SheetSnap.full.size);
    });

    test('fullFractionFor prefers a shorter sheet (no floor) when crowded', () {
      // A reservation larger than half the viewport yields a sub-0.5 cap rather
      // than clamping back up into the chips.
      final f = SheetSnap.fullFractionFor(
          topReservedPx: 600, availableHeight: 800);
      expect(f, closeTo((800 - 600) / 800, 1e-9));
      expect(f, lessThan(0.5));
    });

    test('fullFractionFor falls back to the constant when height unknown', () {
      expect(
        SheetSnap.fullFractionFor(topReservedPx: 130, availableHeight: 0),
        SheetSnap.full.size,
      );
    });

    test('snapSizesFor uses the measured peek and capped full', () {
      expect(SheetSnap.snapSizesFor(0.2, 0.8), [0.2, 0.8]);
    });

    test('nearestFor resolves against the measured peek and capped full', () {
      const peek = 0.2;
      const full = 0.8;
      expect(SheetSnap.nearestFor(peek, peek, full), SheetSnap.peek);
      expect(SheetSnap.nearestFor(0.0, peek, full), SheetSnap.peek);
      expect(SheetSnap.nearestFor(full, peek, full), SheetSnap.full);
      expect(SheetSnap.nearestFor(1.0, peek, full), SheetSnap.full);
    });

    test('nearestFor flips at the midpoint between peek and full', () {
      const peek = 0.2;
      const full = 0.8;
      final mid = (peek + full) / 2;
      expect(SheetSnap.nearestFor(mid - 0.01, peek, full), SheetSnap.peek);
      expect(SheetSnap.nearestFor(mid + 0.01, peek, full), SheetSnap.full);
    });

    test('isFull / isPeek reflect the two named snaps', () {
      expect(SheetSnap.full.isFull, isTrue);
      expect(SheetSnap.peek.isFull, isFalse);
      expect(SheetSnap.peek.isPeek, isTrue);
      expect(SheetSnap.full.isPeek, isFalse);
    });
  });

  group('gemDistanceLabel', () {
    test('returns null when distance is unknown or invalid', () {
      expect(gemDistanceLabel(null), isNull);
      expect(gemDistanceLabel(-1), isNull);
      expect(gemDistanceLabel(double.nan), isNull);
      expect(gemDistanceLabel(double.infinity), isNull);
    });

    test('formats sub-kilometre distances in metres', () {
      expect(gemDistanceLabel(0), '0 m');
      expect(gemDistanceLabel(120.4), '120 m');
      expect(gemDistanceLabel(949), '949 m');
    });

    test('formats kilometres with one decimal up to 10 km', () {
      expect(gemDistanceLabel(1200), '1.2 km');
      expect(gemDistanceLabel(9990), '10.0 km');
    });

    test('formats whole kilometres beyond 10 km', () {
      expect(gemDistanceLabel(12000), '12 km');
      expect(gemDistanceLabel(150000), '150 km');
    });
  });
}

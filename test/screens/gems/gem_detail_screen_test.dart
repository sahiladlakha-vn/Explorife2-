// Tests for the two pure, top-level helpers gem_detail_screen.dart exposes
// specifically for testability (see their own doc comments): the sticky
// CTA's duplicate-add guard, and the Directions button's launch-failure
// detection. Both are exercised directly, with no widget tree, Supabase, or
// platform channels involved — see each function's doc comment for why that
// was the deliberate design.

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:explorife/models/gem.dart';
import 'package:explorife/models/trip_stop.dart';
import 'package:explorife/screens/gems/gem_detail_screen.dart';

Gem _gem(String id) => Gem(id: id, gemName: 'Gem $id', savedAt: DateTime(2026));

TripStop _stop({required String tripId, String? gemId}) => TripStop(
      id: 'stop-${gemId ?? 'custom'}',
      tripId: tripId,
      day: 1,
      slot: 'morning',
      gemId: gemId,
    );

void main() {
  group('gemAlreadyOnTrip', () {
    test('false when the trip has no stops at all', () {
      expect(gemAlreadyOnTrip(_gem('a'), const []), isFalse);
    });

    test('false when the trip has stops, but none reference this gem', () {
      final stops = [
        _stop(tripId: 't1', gemId: 'b'),
        _stop(tripId: 't1'), // a freeform/custom stop, gemId null
      ];
      expect(gemAlreadyOnTrip(_gem('a'), stops), isFalse);
    });

    test('true when a stop already references this exact gem id', () {
      final stops = [
        _stop(tripId: 't1', gemId: 'b'),
        _stop(tripId: 't1', gemId: 'a'),
      ];
      expect(gemAlreadyOnTrip(_gem('a'), stops), isTrue);
    });
  });

  group('attemptExternalLaunch', () {
    test('true when the launcher reports success', () async {
      final result = await attemptExternalLaunch(
        Uri.parse('https://example.com'),
        launcher: (uri, {mode = LaunchMode.platformDefault}) async => true,
      );
      expect(result, isTrue);
    });

    test('false when the launcher reports failure (no maps app, etc.)',
        () async {
      final result = await attemptExternalLaunch(
        Uri.parse('https://example.com'),
        launcher: (uri, {mode = LaunchMode.platformDefault}) async => false,
      );
      expect(result, isFalse);
    });

    test('false (not a thrown exception) when the launcher itself throws',
        () async {
      final result = await attemptExternalLaunch(
        Uri.parse('https://example.com'),
        launcher: (uri, {mode = LaunchMode.platformDefault}) async =>
            throw Exception('platform channel unavailable'),
      );
      expect(result, isFalse);
    });
  });
}

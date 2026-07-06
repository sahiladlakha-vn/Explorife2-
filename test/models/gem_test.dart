// Pure unit tests for Gem.fromJson — no Supabase / network / widget deps, so
// they run fast and deterministically. Covers the coordinate-parsing branches
// (GeoJSON [lng,lat] list vs {lat,lng} map) and the field fallbacks.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/gem.dart';

void main() {
  group('Gem.fromJson', () {
    test('parses gem_coords as a GeoJSON [lng, lat] list', () {
      final gem = Gem.fromJson({
        'id': 'g1',
        'gem_name': 'Hidden Rooftop',
        'category': 'viewpoint',
        'gem_coords': [106.7, 10.78], // [lng, lat]
        'saved_at': '2026-01-02T03:04:05.000Z',
      });

      expect(gem.id, 'g1');
      expect(gem.gemName, 'Hidden Rooftop');
      expect(gem.longitude, 106.7);
      expect(gem.latitude, 10.78);
      expect(gem.hasCoords, isTrue);
    });

    test('parses gem_coords as a {lat, lng} map', () {
      final gem = Gem.fromJson({
        'id': 'g2',
        'gem_name': 'Cave Pool',
        'gem_coords': {'lat': 20.5, 'lng': 105.1},
        'saved_at': '2026-01-02T03:04:05.000Z',
      });

      expect(gem.latitude, 20.5);
      expect(gem.longitude, 105.1);
      expect(gem.hasCoords, isTrue);
    });

    test('falls back to "Unnamed Gem" when gem_name is missing', () {
      final gem = Gem.fromJson({'id': 'g3', 'saved_at': ''});
      expect(gem.gemName, 'Unnamed Gem');
      expect(gem.hasCoords, isFalse);
    });

    test('falls back to DateTime.now() for an unparseable saved_at', () {
      final before = DateTime.now();
      final gem = Gem.fromJson({'id': 'g4', 'saved_at': 'not-a-date'});
      final after = DateTime.now();

      expect(
        gem.savedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        gem.savedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('displayCategory capitalises; emoji maps known categories', () {
      final hiking = Gem.fromJson({
        'id': 'g5',
        'gem_name': 'Ridge Trail',
        'category': 'hiking',
        'saved_at': '',
      });
      expect(hiking.displayCategory, 'Hiking');
      expect(hiking.emoji, '🥾');

      final unknown = Gem.fromJson({'id': 'g6', 'gem_name': 'X', 'saved_at': ''});
      expect(unknown.displayCategory, 'Unknown');
      expect(unknown.emoji, '📍');
    });

    test('parses and serializes the first-class tagline column', () {
      final gem = Gem.fromJson({
        'id': 'g7',
        'gem_name': 'Rooftop',
        'tagline': 'best sunset in town',
        'saved_at': '',
      });
      expect(gem.tagline, 'best sunset in town');

      final row = gem.toInsert(userId: 'u1', lat: 1, lng: 2);
      expect(row['tagline'], 'best sunset in town');
    });

    test('tagline is null when absent', () {
      final gem = Gem.fromJson({'id': 'g8', 'gem_name': 'X', 'saved_at': ''});
      expect(gem.tagline, isNull);
    });

    test('reads dropperHandle from a to-one profiles embed (map)', () {
      final gem = Gem.fromJson({
        'id': 'g9',
        'gem_name': 'X',
        'saved_at': '',
        'profiles': {'display_name': 'toan'},
      });
      expect(gem.dropperHandle, 'toan');
    });

    test('reads dropperHandle from a to-many profiles embed (list)', () {
      final gem = Gem.fromJson({
        'id': 'g10',
        'gem_name': 'X',
        'saved_at': '',
        'profiles': [
          {'display_name': 'lan'},
        ],
      });
      expect(gem.dropperHandle, 'lan');
    });

    test('dropperHandle is null when the profiles embed is absent or empty', () {
      expect(
        Gem.fromJson({'id': 'g11', 'gem_name': 'X', 'saved_at': ''}).dropperHandle,
        isNull,
      );
      expect(
        Gem.fromJson({
          'id': 'g12',
          'gem_name': 'X',
          'saved_at': '',
          'profiles': [],
        }).dropperHandle,
        isNull,
      );
    });

    test('dropperHandle is never written back in toInsert', () {
      final gem = Gem.fromJson({
        'id': 'g13',
        'gem_name': 'X',
        'saved_at': '',
        'profiles': {'display_name': 'toan'},
      });
      final row = gem.toInsert(userId: 'u1', lat: 1, lng: 2);
      expect(row.containsKey('profiles'), isFalse);
      expect(row.containsKey('dropper_handle'), isFalse);
    });
  });
}

// Tests for the Tilequery-POI-to-Gem-category allowlist. Every case here
// mirrors a real (class/type, maki) pair actually returned by the Mapbox
// Tilequery API for Hanoi and Ho Chi Minh City (pulled directly on
// 2026-08-28) — not invented examples — so this locks in the real mapping
// decisions, especially the confirmed memorial/monument → heritage call.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/services/mapbox_tilequery_service.dart';
import 'package:explorife/core/services/poi_category_filter.dart';

NearbyPoi _poi({String? category, String? maki}) => NearbyPoi(
      name: 'Test POI',
      category: category,
      lat: 0,
      lng: 0,
      maki: maki,
    );

void main() {
  group('mapPoiToGemCategory — included (real Tilequery samples)', () {
    test('restaurant maps to food', () {
      expect(mapPoiToGemCategory(_poi(category: 'Restaurant', maki: 'restaurant')),
          'food');
    });

    test('cafe maps to food', () {
      expect(mapPoiToGemCategory(_poi(category: 'Cafe', maki: 'cafe')), 'food');
    });

    test('place of worship maps to temple', () {
      expect(
          mapPoiToGemCategory(
              _poi(category: 'Place Of Worship', maki: 'place-of-worship')),
          'temple');
      expect(
          mapPoiToGemCategory(
              _poi(category: 'Place Of Worship', maki: 'religious-buddhist')),
          'temple');
    });

    test('park maps to nature', () {
      expect(mapPoiToGemCategory(_poi(category: 'Park', maki: 'park')), 'nature');
    });

    test('attraction maps to heritage', () {
      expect(mapPoiToGemCategory(_poi(category: 'Attraction', maki: 'attraction')),
          'heritage');
    });

    test('memorial/monument maps to heritage — confirmed decision', () {
      expect(mapPoiToGemCategory(_poi(category: 'Memorial', maki: 'monument')),
          'heritage');
    });
  });

  group('mapPoiToGemCategory — excluded (real Tilequery samples)', () {
    test('government office is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Government', maki: 'marker')),
          isNull);
    });

    test('townhall is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Townhall', maki: 'town-hall')),
          isNull);
    });

    test('parking is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Parking', maki: 'parking')),
          isNull);
    });

    test('office building is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Office', maki: 'marker')),
          isNull);
    });

    test('bank is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Bank', maki: 'bank')), isNull);
    });

    test('lodging/hotel is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Hotel', maki: 'lodging')),
          isNull);
    });

    test('generic retail (pharmacy, shop, etc.) is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Chemist', maki: 'shop')), isNull);
      expect(mapPoiToGemCategory(_poi(category: 'Jewelry', maki: 'jewelry-store')),
          isNull);
    });

    test('generic unlabeled building is excluded', () {
      expect(mapPoiToGemCategory(_poi(category: 'Yes', maki: 'marker')), isNull);
    });

    test('playground is excluded (park_like class, not itself a destination)',
        () {
      expect(mapPoiToGemCategory(_poi(category: 'Playground', maki: 'marker')),
          isNull);
    });
  });

  group('filterTravelRelevantPois', () {
    test('keeps only travel-relevant POIs, preserving order', () {
      final pois = [
        _poi(category: 'Restaurant', maki: 'restaurant'),
        _poi(category: 'Government', maki: 'marker'),
        _poi(category: 'Park', maki: 'park'),
        _poi(category: 'Parking', maki: 'parking'),
      ];
      final result = filterTravelRelevantPois(pois);
      expect(result.map((p) => p.category), ['Restaurant', 'Park']);
    });
  });
}

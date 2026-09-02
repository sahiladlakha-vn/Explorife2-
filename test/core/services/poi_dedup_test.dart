import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/services/poi_dedup.dart';
import 'package:explorife/core/services/mapbox_tilequery_service.dart';
import 'package:explorife/models/gem.dart';

Gem _gem({required String name, required double lat, required double lng}) =>
    Gem(id: 'g1', gemName: name, latitude: lat, longitude: lng, savedAt: DateTime(2026));

NearbyPoi _poi({required String name, required double lat, required double lng}) =>
    NearbyPoi(name: name, lat: lat, lng: lng);

void main() {
  group('placeNamesLikelyMatch', () {
    test('matches across Vietnamese diacritics vs. plain ASCII', () {
      expect(placeNamesLikelyMatch('Khue Van Cac', 'Khuê Văn Các'), isTrue);
    });

    test('matches identical names', () {
      expect(placeNamesLikelyMatch('Temple of Literature', 'Temple of Literature'),
          isTrue);
    });

    test('matches when one name contains the other', () {
      expect(placeNamesLikelyMatch('Hoan Kiem Lake', 'Ho Guom Hoan Kiem Lake Park'),
          isTrue);
    });

    test('does not match unrelated short generic words (containment branch)', () {
      expect(placeNamesLikelyMatch('Park', 'Parking Garage'), isFalse);
    });

    test('does not match genuinely different places', () {
      expect(placeNamesLikelyMatch('Cafe Napoli', 'City Hall'), isFalse);
    });

    test('empty names never match', () {
      expect(placeNamesLikelyMatch('', 'Anything'), isFalse);
      expect(placeNamesLikelyMatch('Anything', ''), isFalse);
    });
  });

  group('sameRealPlace / excludeDuplicatesOf', () {
    test('suppresses a POI within the dedup radius with a matching name', () {
      final gem = _gem(name: 'Khue Van Cac', lat: 21.028583, lng: 105.835889);
      final poi = _poi(name: 'Khuê Văn Các', lat: 21.028600, lng: 105.835900);
      expect(sameRealPlace(gem, poi), isTrue);
      expect(excludeDuplicatesOf([poi], [gem]), isEmpty);
    });

    test('keeps a POI far outside the dedup radius even with a matching name', () {
      final gem = _gem(name: 'Khue Van Cac', lat: 21.028583, lng: 105.835889);
      final poi = _poi(name: 'Khuê Văn Các', lat: 21.05, lng: 105.90);
      expect(sameRealPlace(gem, poi), isFalse);
      expect(excludeDuplicatesOf([poi], [gem]), [poi]);
    });

    test('keeps a nearby but differently-named POI (adjacent, not duplicate)', () {
      final gem = _gem(name: 'Khue Van Cac', lat: 21.028583, lng: 105.835889);
      final poi = _poi(name: 'Cà Phê Văn Miêu', lat: 21.028590, lng: 105.835895);
      expect(sameRealPlace(gem, poi), isFalse);
      expect(excludeDuplicatesOf([poi], [gem]), [poi]);
    });

    test('a gem with no coordinates never suppresses anything', () {
      final gem = Gem(id: 'g2', gemName: 'No Coords Gem', savedAt: DateTime(2026));
      final poi = _poi(name: 'No Coords Gem', lat: 21.0, lng: 105.8);
      expect(sameRealPlace(gem, poi), isFalse);
    });

    test('excludeDuplicatesOf is a no-op with no gems or no pois', () {
      final poi = _poi(name: 'X', lat: 0, lng: 0);
      expect(excludeDuplicatesOf([poi], []), [poi]);
      expect(excludeDuplicatesOf([], [_gem(name: 'Y', lat: 0, lng: 0)]), isEmpty);
    });
  });
}

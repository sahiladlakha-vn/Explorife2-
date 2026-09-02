import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/tour.dart';

void main() {
  group('Tour.fromJson', () {
    test('parses a fully-populated row', () {
      final tour = Tour.fromJson({
        'id': 't1',
        'name': 'Ha Long Bay Day Cruise',
        'photos': ['a.jpg', 'b.jpg'],
        'category': 'coastal',
        'price_from': 1200000,
        'currency': 'VND',
        'duration_label': 'Full day',
        'cancellation_policy': 'Free up to 24h before',
        'pickup_included': true,
        'pickup_detail': 'Hotel pickup in Old Quarter',
        'guide_languages': ['English', 'Vietnamese'],
        'includes': ['Lunch', 'Kayaking'],
        'itinerary': [
          {'title': 'Pickup', 'description': 'From your hotel'},
          {'title': 'Board the cruise'},
        ],
        'highlights': ['UNESCO site'],
        'full_description': 'A full day cruise...',
        'is_curated': true,
        'created_at': '2026-09-01T00:00:00Z',
      });

      expect(tour.id, 't1');
      expect(tour.coverPhoto, 'a.jpg');
      expect(tour.displayCategory, 'Coastal');
      expect(tour.priceFrom, 1200000);
      expect(tour.pickupIncluded, isTrue);
      expect(tour.guideLanguages, ['English', 'Vietnamese']);
      expect(tour.itinerary.length, 2);
      expect(tour.itinerary[0].title, 'Pickup');
      expect(tour.itinerary[0].description, 'From your hotel');
      expect(tour.itinerary[1].description, isNull);
      expect(tour.isCurated, isTrue);
    });

    test('sparse row falls back safely, never throws', () {
      final tour = Tour.fromJson({
        'id': 't2',
        'price_from': null,
        'created_at': null,
      });

      expect(tour.name, 'Unnamed tour');
      expect(tour.photos, isEmpty);
      expect(tour.coverPhoto, isNull);
      expect(tour.priceFrom, 0);
      expect(tour.currency, 'VND');
      expect(tour.pickupIncluded, isFalse);
      expect(tour.guideLanguages, isEmpty);
      expect(tour.itinerary, isEmpty);
      expect(tour.isCurated, isFalse);
      expect(tour.displayCategory, 'Experience');
      expect(tour.emoji, '🧭');
    });
  });
}

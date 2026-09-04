import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/restaurant.dart';

void main() {
  group('Restaurant.fromJson', () {
    test('parses a fully-populated verified row, linked to a Gem', () {
      final restaurant = Restaurant.fromJson({
        'id': 'r1',
        'owner_id': 'owner1',
        'gem_id': 'gem1',
        'name': 'Pho 24',
        'category': 'food',
        'cuisine_type': ['Local', 'Street Food'],
        'price_range': '\$\$',
        'gallery': ['a.jpg', 'b.jpg'],
        'address': 'Hoan Kiem District, Hanoi',
        'latitude': 21.0285,
        'longitude': 105.8542,
        'phone': '+84123456789',
        'opening_hours': '7am-10pm daily',
        'dietary_options': ['Vegan', 'Gluten-free'],
        'reservation_option': true,
        'business_license_url': 'https://example.com/license.pdf',
        'verification_status': 'verified',
        'verified_by': 'admin1',
        'verified_at': '2026-09-05T00:00:00Z',
        'created_at': '2026-09-01T00:00:00Z',
      });

      expect(restaurant.id, 'r1');
      expect(restaurant.gemId, 'gem1');
      expect(restaurant.category, 'food');
      expect(restaurant.cuisineType, ['Local', 'Street Food']);
      expect(restaurant.priceRange, PriceRange.medium);
      expect(restaurant.coverPhoto, 'a.jpg');
      expect(restaurant.dietaryOptions, ['Vegan', 'Gluten-free']);
      expect(restaurant.reservationOption, isTrue);
      expect(restaurant.businessLicenseUrl, 'https://example.com/license.pdf');
      expect(restaurant.verificationStatus, RestaurantVerificationStatus.verified);
      expect(restaurant.verifiedBy, 'admin1');
    });

    test('an unlinked, pending listing falls back safely', () {
      final restaurant = Restaurant.fromJson({
        'id': 'r2',
        'owner_id': 'owner2',
        'name': 'New Place',
        'price_range': '\$',
        'address': '123 Street',
        'latitude': 10.0,
        'longitude': 106.0,
        'phone': '999',
        'opening_hours': '24/7',
      });

      expect(restaurant.gemId, isNull);
      expect(restaurant.category, 'food');
      expect(restaurant.priceRange, PriceRange.low);
      expect(restaurant.cuisineType, isEmpty);
      expect(restaurant.dietaryOptions, isEmpty);
      expect(restaurant.reservationOption, isFalse);
      expect(restaurant.businessLicenseUrl, isNull);
      expect(restaurant.coverPhoto, isNull);
      expect(restaurant.verificationStatus, RestaurantVerificationStatus.pending);
      expect(restaurant.verifiedBy, isNull);
      expect(restaurant.isRetracted, isFalse);
      expect(restaurant.deletedAt, isNull);
    });

    test('a retracted (soft-deleted) listing parses deletedAt / isRetracted', () {
      final restaurant = Restaurant.fromJson({
        'id': 'r3',
        'owner_id': 'owner1',
        'name': 'Closed Place',
        'price_range': '\$\$\$',
        'address': 'addr',
        'latitude': 1,
        'longitude': 2,
        'phone': '111',
        'opening_hours': '9-5',
        'verification_status': 'verified',
        'deleted_at': '2026-09-05T12:00:00Z',
      });
      expect(restaurant.isRetracted, isTrue);
      expect(restaurant.deletedAt, DateTime.parse('2026-09-05T12:00:00Z'));
    });
  });

  group('Restaurant.toInsert', () {
    test('never includes verification-status fields — server-side only', () {
      final restaurant = Restaurant(
        id: 'r4',
        ownerId: 'owner4',
        name: 'Test',
        priceRange: PriceRange.low,
        address: 'addr',
        latitude: 1,
        longitude: 2,
        phone: '000',
        openingHours: '9-5',
        createdAt: DateTime(2026),
      );
      final json = restaurant.toInsert();
      expect(json.containsKey('verification_status'), isFalse);
      expect(json.containsKey('verified_by'), isFalse);
      expect(json.containsKey('verified_at'), isFalse);
      expect(json.containsKey('id'), isFalse);
      // category is fixed server-side default 'food' — not sent by the
      // client at all, same "server owns this" reasoning as verification
      // fields (there's no UI to pick a different one, so nothing to send).
      expect(json.containsKey('category'), isFalse);
    });

    test('omits business_license_url when absent, includes it when set', () {
      final withoutLicense = Restaurant(
        id: 'r5', ownerId: 'o', name: 'n', priceRange: PriceRange.low,
        address: 'a', latitude: 0, longitude: 0, phone: 'p', openingHours: 'h',
        createdAt: DateTime(2026),
      );
      expect(withoutLicense.toInsert().containsKey('business_license_url'), isFalse);

      final withLicense = Restaurant(
        id: 'r6', ownerId: 'o', name: 'n', priceRange: PriceRange.low,
        address: 'a', latitude: 0, longitude: 0, phone: 'p', openingHours: 'h',
        businessLicenseUrl: 'https://example.com/l.pdf',
        createdAt: DateTime(2026),
      );
      expect(withLicense.toInsert()['business_license_url'], 'https://example.com/l.pdf');
    });
  });

  test('PriceRange and RestaurantVerificationStatus wire round-trip', () {
    for (final p in PriceRange.values) {
      expect(PriceRange.fromWire(p.wire), p);
    }
    for (final s in RestaurantVerificationStatus.values) {
      expect(RestaurantVerificationStatus.fromWire(s.wire), s);
    }
  });

  group('RestaurantMenuItem', () {
    test('fromJson parses a fully-populated row', () {
      final item = RestaurantMenuItem.fromJson({
        'id': 'm1',
        'restaurant_id': 'r1',
        'dish_name': 'Pho Bo',
        'price_amount': 45000,
        'currency': 'VND',
        'photo_url': 'dish.jpg',
        'display_order': 2,
      });
      expect(item.dishName, 'Pho Bo');
      expect(item.priceAmount, 45000);
      expect(item.photoUrl, 'dish.jpg');
      expect(item.displayOrder, 2);
    });

    test('toInsert includes the given restaurantId and omits null photoUrl', () {
      const item = RestaurantMenuItem(
          id: '', restaurantId: '', dishName: 'Bun Cha', priceAmount: 40000);
      final json = item.toInsert('r7');
      expect(json['restaurant_id'], 'r7');
      expect(json.containsKey('photo_url'), isFalse);
    });
  });
}

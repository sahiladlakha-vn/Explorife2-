import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/restaurant.dart';
import 'package:explorife/repositories/restaurant_repository.dart';

Restaurant _restaurant({
  RestaurantVerificationStatus status = RestaurantVerificationStatus.verified,
  DateTime? deletedAt,
}) =>
    Restaurant(
      id: 'r1',
      ownerId: 'owner1',
      name: 'Test Restaurant',
      priceRange: PriceRange.low,
      address: 'addr',
      latitude: 0,
      longitude: 0,
      phone: '000',
      openingHours: '9-5',
      verificationStatus: status,
      deletedAt: deletedAt,
      createdAt: DateTime(2026),
    );

void main() {
  group('liveVerifiedRestaurant', () {
    // Applies the same deleted_at/retraction backstop the Attraction
    // deleted_at audit added — built in from day one here instead of
    // waiting for a second review pass to find the gap. See
    // docs/audits/attraction-business-profile-2026-09-04.md's "Post-review
    // fix 2" for the original finding this generalizes.
    test('returns null for a retracted listing even though it is still '
        '"verified"', () {
      final retracted = _restaurant(
        status: RestaurantVerificationStatus.verified,
        deletedAt: DateTime(2026, 9, 5),
      );
      expect(retracted.verificationStatus, RestaurantVerificationStatus.verified);
      expect(liveVerifiedRestaurant(retracted), isNull);
    });

    test('returns the restaurant for a real live verified listing', () {
      final live = _restaurant(status: RestaurantVerificationStatus.verified);
      expect(liveVerifiedRestaurant(live), same(live));
    });

    test('returns null for a non-verified listing (pending/rejected)', () {
      expect(
          liveVerifiedRestaurant(
              _restaurant(status: RestaurantVerificationStatus.pending)),
          isNull);
      expect(
          liveVerifiedRestaurant(
              _restaurant(status: RestaurantVerificationStatus.rejected)),
          isNull);
    });

    test('returns null for a null input', () {
      expect(liveVerifiedRestaurant(null), isNull);
    });
  });
}

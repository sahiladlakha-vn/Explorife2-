import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/attraction.dart';
import 'package:explorife/repositories/attraction_repository.dart';

Attraction _attraction({
  AttractionVerificationStatus status = AttractionVerificationStatus.verified,
  DateTime? deletedAt,
}) =>
    Attraction(
      id: 'a1',
      ownerId: 'owner1',
      name: 'Test Attraction',
      category: 'heritage',
      address: 'addr',
      latitude: 0,
      longitude: 0,
      openingHours: '9-5',
      entryFeeType: EntryFeeType.free,
      description: 'desc',
      verificationStatus: status,
      deletedAt: deletedAt,
      createdAt: DateTime(2026),
    );

void main() {
  group('liveVerifiedAttraction', () {
    // Regression coverage for the gap found in the deleted_at audit:
    // retract_attraction sets deleted_at but deliberately leaves
    // verification_status untouched, so a retracted listing can still
    // report verification_status == 'verified' forever. This is the
    // client-side backstop behind the query-level `deleted_at is null`
    // filter in fetchVerifiedForGem/fetchVerified/fetchPending.
    test('returns null for a retracted listing even though it is still '
        '"verified"', () {
      final retracted = _attraction(
        status: AttractionVerificationStatus.verified,
        deletedAt: DateTime(2026, 9, 4),
      );
      expect(retracted.verificationStatus, AttractionVerificationStatus.verified);
      expect(liveVerifiedAttraction(retracted), isNull);
    });

    test('returns the attraction for a real live verified listing', () {
      final live = _attraction(status: AttractionVerificationStatus.verified);
      expect(liveVerifiedAttraction(live), same(live));
    });

    test('returns null for a non-verified listing (pending/rejected)', () {
      expect(
          liveVerifiedAttraction(_attraction(status: AttractionVerificationStatus.pending)),
          isNull);
      expect(
          liveVerifiedAttraction(_attraction(status: AttractionVerificationStatus.rejected)),
          isNull);
    });

    test('returns null for a null input', () {
      expect(liveVerifiedAttraction(null), isNull);
    });
  });
}

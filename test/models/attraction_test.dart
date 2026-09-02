import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/attraction.dart';

void main() {
  group('Attraction.fromJson', () {
    test('parses a fully-populated verified row, linked to a Gem', () {
      final attraction = Attraction.fromJson({
        'id': 'a1',
        'owner_id': 'owner1',
        'gem_id': 'gem1',
        'name': 'Temple of Literature',
        'category': 'heritage',
        'gallery': ['a.jpg', 'b.jpg'],
        'address': 'Dong Da District, Hanoi',
        'latitude': 21.0135,
        'longitude': 105.8225,
        'opening_hours': '8am-5pm daily',
        'entry_fee_type': 'paid',
        'entry_fee_amount': 30000,
        'currency': 'VND',
        'description': 'A historic temple.',
        'certification_urls': [],
        'recommended_duration': '1-2 hours',
        'verification_status': 'verified',
        'verified_by': 'admin1',
        'verified_at': '2026-09-04T00:00:00Z',
        'created_at': '2026-09-01T00:00:00Z',
      });

      expect(attraction.id, 'a1');
      expect(attraction.gemId, 'gem1');
      expect(attraction.category, 'heritage');
      expect(attraction.coverPhoto, 'a.jpg');
      expect(attraction.entryFeeType, EntryFeeType.paid);
      expect(attraction.isFree, isFalse);
      expect(attraction.entryFeeAmount, 30000);
      expect(attraction.verificationStatus, AttractionVerificationStatus.verified);
      expect(attraction.verifiedBy, 'admin1');
    });

    test('a free, unlinked, pending listing falls back safely', () {
      final attraction = Attraction.fromJson({
        'id': 'a2',
        'owner_id': 'owner2',
        'name': 'New Place',
        'category': 'nature',
        'address': '123 Street',
        'latitude': 10.0,
        'longitude': 106.0,
        'opening_hours': '24/7',
        'entry_fee_type': 'free',
        'description': 'test',
      });

      expect(attraction.gemId, isNull);
      expect(attraction.isFree, isTrue);
      expect(attraction.entryFeeAmount, isNull);
      expect(attraction.coverPhoto, isNull);
      expect(attraction.verificationStatus, AttractionVerificationStatus.pending);
      expect(attraction.verifiedBy, isNull);
      expect(attraction.isRetracted, isFalse);
      expect(attraction.deletedAt, isNull);
    });

    test('a retracted (soft-deleted) listing parses deletedAt / isRetracted', () {
      final attraction = Attraction.fromJson({
        'id': 'a6',
        'owner_id': 'owner1',
        'name': 'Closed Place',
        'category': 'food',
        'address': 'addr',
        'latitude': 1,
        'longitude': 2,
        'opening_hours': '9-5',
        'entry_fee_type': 'free',
        'description': 'desc',
        'verification_status': 'verified',
        'deleted_at': '2026-09-04T12:00:00Z',
      });
      expect(attraction.isRetracted, isTrue);
      expect(attraction.deletedAt, DateTime.parse('2026-09-04T12:00:00Z'));
    });
  });

  group('Attraction.toInsert', () {
    test('never includes verification-status fields — server-side only', () {
      final attraction = Attraction(
        id: 'a3',
        ownerId: 'owner3',
        name: 'Test',
        category: 'food',
        address: 'addr',
        latitude: 1,
        longitude: 2,
        openingHours: '9-5',
        entryFeeType: EntryFeeType.free,
        description: 'desc',
        createdAt: DateTime(2026),
      );
      final json = attraction.toInsert();
      expect(json.containsKey('verification_status'), isFalse);
      expect(json.containsKey('verified_by'), isFalse);
      expect(json.containsKey('verified_at'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });

    test('omits entry_fee_amount when free, includes it when paid', () {
      final free = Attraction(
        id: 'a4', ownerId: 'o', name: 'n', category: 'food', address: 'a',
        latitude: 0, longitude: 0, openingHours: 'h',
        entryFeeType: EntryFeeType.free, description: 'd', createdAt: DateTime(2026),
      );
      expect(free.toInsert().containsKey('entry_fee_amount'), isFalse);

      final paid = Attraction(
        id: 'a5', ownerId: 'o', name: 'n', category: 'food', address: 'a',
        latitude: 0, longitude: 0, openingHours: 'h',
        entryFeeType: EntryFeeType.paid, entryFeeAmount: 50000,
        description: 'd', createdAt: DateTime(2026),
      );
      expect(paid.toInsert()['entry_fee_amount'], 50000);
    });
  });

  test('EntryFeeType and AttractionVerificationStatus wire round-trip', () {
    expect(EntryFeeType.fromWire(EntryFeeType.free.wire), EntryFeeType.free);
    expect(EntryFeeType.fromWire(EntryFeeType.paid.wire), EntryFeeType.paid);
    for (final s in AttractionVerificationStatus.values) {
      expect(AttractionVerificationStatus.fromWire(s.wire), s);
    }
  });
}

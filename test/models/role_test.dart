import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/role.dart';

void main() {
  group('Role wire round-trip', () {
    for (final role in Role.values) {
      test('${role.name} round-trips through wire/fromWire', () {
        expect(Role.fromWire(role.wire), role);
      });
    }
  });

  test('fromWire defaults to traveler for null/unrecognized values', () {
    expect(Role.fromWire(null), Role.traveler);
    expect(Role.fromWire('nonsense'), Role.traveler);
  });

  test('isAdminTier is true for exactly the 4 admin-tier roles', () {
    expect(Role.contentModerator.isAdminTier, isTrue);
    expect(Role.regionalAdmin.isAdminTier, isTrue);
    expect(Role.superAdmin.isAdminTier, isTrue);
    expect(Role.financeAdmin.isAdminTier, isTrue);
    expect(Role.traveler.isAdminTier, isFalse);
    expect(Role.guide.isAdminTier, isFalse);
    expect(Role.businessOwner.isAdminTier, isFalse);
  });

  test('wire values match the user_role Postgres enum exactly', () {
    expect(Role.traveler.wire, 'traveler');
    expect(Role.guide.wire, 'guide');
    expect(Role.businessOwner.wire, 'business_owner');
    expect(Role.contentModerator.wire, 'content_moderator');
    expect(Role.regionalAdmin.wire, 'regional_admin');
    expect(Role.superAdmin.wire, 'super_admin');
    expect(Role.financeAdmin.wire, 'finance_admin');
  });
}

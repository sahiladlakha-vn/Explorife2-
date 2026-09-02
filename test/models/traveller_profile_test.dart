import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/traveller_profile.dart';

void main() {
  group('TravellerProfile.fromJson', () {
    test('parses a fully-populated row', () {
      final profile = TravellerProfile.fromJson({
        'user_id': 'u1',
        'date_of_birth': '1995-06-15',
        'gender': 'female',
        'nationality': 'Vietnam',
        'phone': '+84123456789',
        'login_method': 'google',
        'preferred_language': 'en',
        'account_status': 'active',
        'interests': ['adventure', 'food'],
        'travel_style': 'solo',
        'budget_range': '\$\$',
        'home_location': 'Hanoi',
        'verification_status': 'id_verified',
        'emergency_contact': 'Jane Doe, +84987654321',
      });

      expect(profile.userId, 'u1');
      expect(profile.dateOfBirth, DateTime(1995, 6, 15));
      expect(profile.gender, Gender.female);
      expect(profile.nationality, 'Vietnam');
      expect(profile.loginMethod, LoginMethod.google);
      expect(profile.accountStatus, TravellerAccountStatus.active);
      expect(profile.interests, [TravelInterest.adventure, TravelInterest.food]);
      expect(profile.travelStyle, TravelStyle.solo);
      expect(profile.budgetRange, BudgetRange.medium);
      expect(profile.verificationStatus, VerificationStatus.idVerified);
      expect(profile.emergencyContact, 'Jane Doe, +84987654321');
    });

    test('sparse row falls back safely, never throws', () {
      final profile = TravellerProfile.fromJson({'user_id': 'u2'});
      expect(profile.userId, 'u2');
      expect(profile.dateOfBirth, isNull);
      expect(profile.gender, isNull);
      expect(profile.accountStatus, TravellerAccountStatus.active);
      expect(profile.interests, isEmpty);
      expect(profile.verificationStatus, VerificationStatus.unverified);
    });
  });

  group('LoginMethod.fromAuthProvider', () {
    test('maps real Supabase provider strings', () {
      expect(LoginMethod.fromAuthProvider('google'), LoginMethod.google);
      expect(LoginMethod.fromAuthProvider('github'), LoginMethod.github);
    });

    test('returns null for a provider this app does not actually support', () {
      // The source schema lists Email/Facebook/Apple, but no working
      // sign-in flow exists for any of them (see AuthProvider) — this
      // enum deliberately only recognizes what's real.
      expect(LoginMethod.fromAuthProvider('facebook'), isNull);
      expect(LoginMethod.fromAuthProvider('apple'), isNull);
      expect(LoginMethod.fromAuthProvider('email'), isNull);
    });
  });

  test('BudgetRange wire values are the literal dollar signs, not words', () {
    expect(BudgetRange.low.wire, '\$');
    expect(BudgetRange.medium.wire, '\$\$');
    expect(BudgetRange.high.wire, '\$\$\$');
    expect(BudgetRange.luxury.wire, '\$\$\$\$');
    expect(BudgetRange.fromWire('\$\$\$'), BudgetRange.high);
  });

  test('toUpsert only includes non-null optional fields', () {
    const profile = TravellerProfile(userId: 'u3');
    final json = profile.toUpsert();
    expect(json['user_id'], 'u3');
    expect(json.containsKey('date_of_birth'), isFalse);
    expect(json.containsKey('gender'), isFalse);
    expect(json['account_status'], 'active');
    expect(json['interests'], isEmpty);
    expect(json['verification_status'], 'unverified');
  });
}

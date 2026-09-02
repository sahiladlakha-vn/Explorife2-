import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/auth/permissions.dart';
import 'package:explorife/models/role.dart';

void main() {
  // Transcribed directly from the source "Roles & Permissions" sheet
  // (rows 5-17), in the sheet's own role-column order: Traveller, Guide,
  // Business Owner, Content Moderator, Regional Admin, Super Admin. This
  // test exists to catch any drift between permissions.dart's _matrix and
  // the real spreadsheet — if a cell changes here, it should be because the
  // source sheet changed, not a typo.
  const sheetGrants = <Permission, Map<Role, String>>{
    Permission.browseSearchListings: {
      Role.traveler: 'yes', Role.guide: 'yes', Role.businessOwner: 'yes',
      Role.contentModerator: 'yes', Role.regionalAdmin: 'yes', Role.superAdmin: 'yes',
    },
    Permission.bookHotelTourGuide: {
      Role.traveler: 'yes', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'no',
    },
    Permission.writeReviews: {
      Role.traveler: 'yes', Role.guide: 'yes', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'no',
    },
    Permission.createEditOwnBusinessProfile: {
      Role.traveler: 'no', Role.guide: 'own', Role.businessOwner: 'own',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'yes',
    },
    Permission.manageOwnBookingsCalendar: {
      Role.traveler: 'no', Role.guide: 'own', Role.businessOwner: 'own',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'yes',
    },
    Permission.approveRejectBusinessListings: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'yes', Role.regionalAdmin: 'yes', Role.superAdmin: 'yes',
    },
    Permission.verifyLicensesCertifications: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'own', Role.regionalAdmin: 'yes', Role.superAdmin: 'yes',
    },
    Permission.moderateReviewsContent: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'yes', Role.regionalAdmin: 'yes', Role.superAdmin: 'yes',
    },
    Permission.suspendBanUserOrBusiness: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'own', Role.superAdmin: 'yes',
    },
    Permission.managePaymentsPayouts: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'own', Role.superAdmin: 'yes',
    },
    Permission.viewPlatformAnalytics: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'own', Role.regionalAdmin: 'own', Role.superAdmin: 'yes',
    },
    Permission.manageOtherAdminAccounts: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'yes',
    },
    Permission.assignChangeUserRoles: {
      Role.traveler: 'no', Role.guide: 'no', Role.businessOwner: 'no',
      Role.contentModerator: 'no', Role.regionalAdmin: 'no', Role.superAdmin: 'yes',
    },
  };

  group('hasPermission matches the source Roles & Permissions sheet exactly', () {
    for (final entry in sheetGrants.entries) {
      final permission = entry.key;
      for (final roleEntry in entry.value.entries) {
        final role = roleEntry.key;
        final grant = roleEntry.value;
        test('$permission / $role = $grant', () {
          switch (grant) {
            case 'yes':
              expect(hasPermission(role, permission), isTrue);
              expect(hasPermission(role, permission, isOwnResource: false), isTrue);
              break;
            case 'no':
              expect(hasPermission(role, permission), isFalse);
              expect(hasPermission(role, permission, isOwnResource: true), isFalse);
              break;
            case 'own':
              expect(hasPermission(role, permission), isFalse);
              expect(hasPermission(role, permission, isOwnResource: false), isFalse);
              expect(hasPermission(role, permission, isOwnResource: true), isTrue);
              break;
          }
        });
      }
    }
  });

  group('Role.financeAdmin (resolved Open Decision 2 — not in the source sheet)', () {
    test('can browse & search like everyone else', () {
      expect(hasPermission(Role.financeAdmin, Permission.browseSearchListings), isTrue);
    });

    test('can manage payments/payouts, but only its own', () {
      expect(hasPermission(Role.financeAdmin, Permission.managePaymentsPayouts), isFalse);
      expect(
          hasPermission(Role.financeAdmin, Permission.managePaymentsPayouts,
              isOwnResource: true),
          isTrue);
    });

    test('can view analytics, but only its own', () {
      expect(hasPermission(Role.financeAdmin, Permission.viewPlatformAnalytics), isFalse);
      expect(
          hasPermission(Role.financeAdmin, Permission.viewPlatformAnalytics,
              isOwnResource: true),
          isTrue);
    });

    test('cannot moderate content, approve listings, or manage other admins', () {
      expect(hasPermission(Role.financeAdmin, Permission.moderateReviewsContent), isFalse);
      expect(hasPermission(Role.financeAdmin, Permission.approveRejectBusinessListings),
          isFalse);
      expect(hasPermission(Role.financeAdmin, Permission.manageOtherAdminAccounts), isFalse);
      expect(hasPermission(Role.financeAdmin, Permission.assignChangeUserRoles), isFalse);
    });

    test('cannot book or write reviews (not a traveller/guide capability)', () {
      expect(hasPermission(Role.financeAdmin, Permission.bookHotelTourGuide), isFalse);
      expect(hasPermission(Role.financeAdmin, Permission.writeReviews), isFalse);
    });
  });

  test('an unrecognized combination defaults to denied, never granted', () {
    // Every real (Permission, Role) pair is covered above; this just
    // confirms the fallback direction is fail-closed.
    expect(hasPermission(Role.traveler, Permission.manageOtherAdminAccounts), isFalse);
  });
}

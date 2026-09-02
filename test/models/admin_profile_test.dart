import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/admin_profile.dart';
import 'package:explorife/models/role.dart';

void main() {
  group('AdminRoleTitle.permissionRole (Open Decision 2)', () {
    test('supportStaff maps onto contentModerator\'s permission tier', () {
      expect(AdminRoleTitle.supportStaff.permissionRole, Role.contentModerator);
    });

    test('financeAdmin maps onto its own new tier', () {
      expect(AdminRoleTitle.financeAdmin.permissionRole, Role.financeAdmin);
    });

    test('the 3 matrix-defined titles map onto themselves', () {
      expect(AdminRoleTitle.superAdmin.permissionRole, Role.superAdmin);
      expect(AdminRoleTitle.regionalAdmin.permissionRole, Role.regionalAdmin);
      expect(AdminRoleTitle.contentModerator.permissionRole, Role.contentModerator);
    });
  });

  group('AdminRoleTitle wire round-trip', () {
    for (final title in AdminRoleTitle.values) {
      test('${title.name} round-trips', () {
        expect(AdminRoleTitle.fromWire(title.wire), title);
      });
    }
  });

  group('AdminProfile.fromJson / toInsert', () {
    test('parses a fully-populated row', () {
      final profile = AdminProfile.fromJson({
        'user_id': 'u1',
        'role_title': 'support_staff',
        'managed_profile_types': ['hotel', 'traveller'],
        'assigned_region': 'Ho Chi Minh City',
        'account_status': 'active',
        'two_factor_enabled': false,
        'last_login': '2026-09-03T00:00:00Z',
        'last_login_ip': '1.2.3.4',
        'notes': 'test note',
      });

      expect(profile.userId, 'u1');
      expect(profile.roleTitle, AdminRoleTitle.supportStaff);
      expect(profile.permissionRole, Role.contentModerator);
      expect(profile.managedProfileTypes, [ManagedProfileType.hotel, ManagedProfileType.traveller]);
      expect(profile.assignedRegion, 'Ho Chi Minh City');
      expect(profile.accountStatus, AdminAccountStatus.active);
      expect(profile.twoFactorEnabled, isFalse);
      expect(profile.lastLoginIp, '1.2.3.4');
      expect(profile.notes, 'test note');
    });

    test('toInsert round-trips the essential fields', () {
      const profile = AdminProfile(
        userId: 'u2',
        roleTitle: AdminRoleTitle.financeAdmin,
        managedProfileTypes: [ManagedProfileType.all],
        accountStatus: AdminAccountStatus.suspended,
        twoFactorEnabled: true,
      );
      final json = profile.toInsert();
      expect(json['user_id'], 'u2');
      expect(json['role_title'], 'finance_admin');
      expect(json['managed_profile_types'], ['all']);
      expect(json['account_status'], 'suspended');
      expect(json['two_factor_enabled'], isTrue);
    });
  });
}

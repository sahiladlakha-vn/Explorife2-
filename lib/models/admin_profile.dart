import 'role.dart';

/// The Admin sheet's own 5-value "Role / Title" dropdown — a display/audit
/// label, DISTINCT from [Role] (the 7-value enum actual permission checks
/// key on via `profiles.role`). The source schema's Admin sheet defines 5
/// titles, but the Roles & Permissions matrix only ever defined 3
/// permission tiers among them (Content Moderator, Regional Admin, Super
/// Admin) — Support Staff and Finance Admin had no column at all.
///
/// Resolved with product: Support Staff shares Content Moderator's
/// permission tier exactly (no new tier — [permissionRole] maps it there);
/// Finance Admin gets its own new tier ([Role.financeAdmin] — see
/// permissions.dart's matrix: own-only payments/payouts + own-only
/// analytics, nothing else). This is why two admins can carry different
/// [AdminRoleTitle]s (one `supportStaff`, one `contentModerator`) while
/// [permissionRole] — and therefore everything [hasPermission] grants
/// them — is identical.
enum AdminRoleTitle {
  superAdmin,
  regionalAdmin,
  contentModerator,
  supportStaff,
  financeAdmin;

  String get wire => switch (this) {
        AdminRoleTitle.superAdmin => 'super_admin',
        AdminRoleTitle.regionalAdmin => 'regional_admin',
        AdminRoleTitle.contentModerator => 'content_moderator',
        AdminRoleTitle.supportStaff => 'support_staff',
        AdminRoleTitle.financeAdmin => 'finance_admin',
      };

  static AdminRoleTitle fromWire(String value) => switch (value) {
        'regional_admin' => AdminRoleTitle.regionalAdmin,
        'content_moderator' => AdminRoleTitle.contentModerator,
        'support_staff' => AdminRoleTitle.supportStaff,
        'finance_admin' => AdminRoleTitle.financeAdmin,
        _ => AdminRoleTitle.superAdmin,
      };

  /// The [Role] this title's account should carry on `profiles.role` for
  /// permission checks — see the class doc comment for the Support
  /// Staff -> Content Moderator collapse.
  Role get permissionRole => switch (this) {
        AdminRoleTitle.superAdmin => Role.superAdmin,
        AdminRoleTitle.regionalAdmin => Role.regionalAdmin,
        AdminRoleTitle.contentModerator => Role.contentModerator,
        AdminRoleTitle.supportStaff => Role.contentModerator,
        AdminRoleTitle.financeAdmin => Role.financeAdmin,
      };
}

/// One of the 8 future business profile types (out of scope this phase),
/// or Traveller, or All — [AdminProfile.managedProfileTypes]' allowed
/// values, matching the source schema's multi-select exactly.
enum ManagedProfileType {
  hotel,
  tourOperator,
  guide,
  transportation,
  restaurant,
  attraction,
  wellness,
  retail,
  traveller,
  all;

  String get wire => switch (this) {
        ManagedProfileType.hotel => 'hotel',
        ManagedProfileType.tourOperator => 'tour_operator',
        ManagedProfileType.guide => 'guide',
        ManagedProfileType.transportation => 'transportation',
        ManagedProfileType.restaurant => 'restaurant',
        ManagedProfileType.attraction => 'attraction',
        ManagedProfileType.wellness => 'wellness',
        ManagedProfileType.retail => 'retail',
        ManagedProfileType.traveller => 'traveller',
        ManagedProfileType.all => 'all',
      };

  static ManagedProfileType? fromWire(String value) => switch (value) {
        'hotel' => ManagedProfileType.hotel,
        'tour_operator' => ManagedProfileType.tourOperator,
        'guide' => ManagedProfileType.guide,
        'transportation' => ManagedProfileType.transportation,
        'restaurant' => ManagedProfileType.restaurant,
        'attraction' => ManagedProfileType.attraction,
        'wellness' => ManagedProfileType.wellness,
        'retail' => ManagedProfileType.retail,
        'traveller' => ManagedProfileType.traveller,
        'all' => ManagedProfileType.all,
        _ => null,
      };
}

enum AdminAccountStatus {
  active,
  suspended,
  inactive;

  String get wire => name;

  static AdminAccountStatus fromWire(String value) => switch (value) {
        'suspended' => AdminAccountStatus.suspended,
        'inactive' => AdminAccountStatus.inactive,
        _ => AdminAccountStatus.active,
      };
}

/// Backs `public.admin_profiles`. See that migration's doc comment for
/// which schema fields were deliberately NOT built as stored columns this
/// phase (permissionLevel, actionLog counters, real 2FA) and why.
class AdminProfile {
  final String userId;
  final AdminRoleTitle roleTitle;
  final List<ManagedProfileType> managedProfileTypes;
  final String? assignedRegion;
  final AdminAccountStatus accountStatus;

  /// Stored, but NOT backed by any real MFA enrollment/verification flow
  /// yet — surface this honestly as "Coming soon" in any UI, never as a
  /// toggle that implies it actually secures the account.
  final bool twoFactorEnabled;

  final DateTime? lastLogin;
  final String? lastLoginIp;
  final String? notes;

  const AdminProfile({
    required this.userId,
    required this.roleTitle,
    this.managedProfileTypes = const [],
    this.assignedRegion,
    this.accountStatus = AdminAccountStatus.active,
    this.twoFactorEnabled = false,
    this.lastLogin,
    this.lastLoginIp,
    this.notes,
  });

  /// The actual permission tier this admin's account should carry on
  /// `profiles.role` — see [AdminRoleTitle.permissionRole].
  Role get permissionRole => roleTitle.permissionRole;

  factory AdminProfile.fromJson(Map<String, dynamic> json) => AdminProfile(
        userId: json['user_id'] as String,
        roleTitle: AdminRoleTitle.fromWire(json['role_title'] as String),
        managedProfileTypes: ((json['managed_profile_types'] as List?) ?? const [])
            .map((e) => ManagedProfileType.fromWire(e as String))
            .whereType<ManagedProfileType>()
            .toList(),
        assignedRegion: json['assigned_region'] as String?,
        accountStatus:
            AdminAccountStatus.fromWire(json['account_status'] as String? ?? 'active'),
        twoFactorEnabled: json['two_factor_enabled'] as bool? ?? false,
        lastLogin: json['last_login'] != null
            ? DateTime.tryParse(json['last_login'] as String)
            : null,
        lastLoginIp: json['last_login_ip'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'user_id': userId,
        'role_title': roleTitle.wire,
        'managed_profile_types': managedProfileTypes.map((t) => t.wire).toList(),
        if (assignedRegion != null) 'assigned_region': assignedRegion,
        'account_status': accountStatus.wire,
        'two_factor_enabled': twoFactorEnabled,
        if (notes != null) 'notes': notes,
      };
}

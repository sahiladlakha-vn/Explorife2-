import '../../models/role.dart';

/// One row of the Roles & Permissions matrix — the 13 actions the source
/// schema's "Roles & Permissions" sheet defines. Every permission check in
/// this app should route through [hasPermission] keyed on one of these,
/// not a scattered `role == Role.superAdmin` check re-implemented per
/// screen.
enum Permission {
  browseSearchListings,
  bookHotelTourGuide,
  writeReviews,
  createEditOwnBusinessProfile,
  manageOwnBookingsCalendar,
  approveRejectBusinessListings,
  verifyLicensesCertifications,
  moderateReviewsContent,
  suspendBanUserOrBusiness,
  managePaymentsPayouts,
  viewPlatformAnalytics,
  manageOtherAdminAccounts,
  assignChangeUserRoles,
}

/// A cell in the matrix: denied outright, granted unconditionally, or
/// granted only against a resource the account itself owns (its own
/// business profile, its own region, its own bookings). [hasPermission]'s
/// `isOwnResource` parameter is what [ownOnly] actually gates on.
enum _Grant { no, yes, ownOnly }

/// The Roles & Permissions matrix, transcribed field-for-field from the
/// source schema's "Roles & Permissions" sheet — 7 roles (the sheet's 6,
/// plus [Role.financeAdmin]; see role.dart's doc comment) × 13 actions.
/// Every cell here should be traceable back to that sheet; nothing here was
/// guessed. The one addition — the [Role.financeAdmin] row — resolves the
/// Admin profile sheet's "Finance Admin" title (which the matrix itself
/// never defined a column for): confirmed with product that Finance Admin
/// gets exactly "Manage payments/payouts" and "View platform-wide
/// analytics," both own-only, and nothing else — narrower than every other
/// admin tier, matching a finance-specific role rather than a general
/// moderation one.
///
/// "Support Staff" (the Admin sheet's other undefined title) is NOT a row
/// here — confirmed with product that it shares [Role.contentModerator]'s
/// permission tier entirely; it only exists as a display label
/// (`AdminRoleTitle.supportStaff` in admin_profile.dart), not a distinct
/// permission tier.
const Map<Permission, Map<Role, _Grant>> _matrix = {
  Permission.browseSearchListings: {
    Role.traveler: _Grant.yes,
    Role.guide: _Grant.yes,
    Role.businessOwner: _Grant.yes,
    Role.contentModerator: _Grant.yes,
    Role.regionalAdmin: _Grant.yes,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.yes,
  },
  Permission.bookHotelTourGuide: {
    Role.traveler: _Grant.yes,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.no,
    Role.financeAdmin: _Grant.no,
  },
  Permission.writeReviews: {
    Role.traveler: _Grant.yes,
    Role.guide: _Grant.yes,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.no,
    Role.financeAdmin: _Grant.no,
  },
  Permission.createEditOwnBusinessProfile: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.ownOnly,
    Role.businessOwner: _Grant.ownOnly,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.manageOwnBookingsCalendar: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.ownOnly,
    Role.businessOwner: _Grant.ownOnly,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.approveRejectBusinessListings: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.yes,
    Role.regionalAdmin: _Grant.yes,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.verifyLicensesCertifications: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.ownOnly,
    Role.regionalAdmin: _Grant.yes,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.moderateReviewsContent: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.yes,
    Role.regionalAdmin: _Grant.yes,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.suspendBanUserOrBusiness: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.ownOnly,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.managePaymentsPayouts: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.ownOnly,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.ownOnly,
  },
  Permission.viewPlatformAnalytics: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.ownOnly,
    Role.regionalAdmin: _Grant.ownOnly,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.ownOnly,
  },
  Permission.manageOtherAdminAccounts: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
  Permission.assignChangeUserRoles: {
    Role.traveler: _Grant.no,
    Role.guide: _Grant.no,
    Role.businessOwner: _Grant.no,
    Role.contentModerator: _Grant.no,
    Role.regionalAdmin: _Grant.no,
    Role.superAdmin: _Grant.yes,
    Role.financeAdmin: _Grant.no,
  },
};

/// Whether [role] may perform [permission]. [isOwnResource] must be true
/// when the caller has independently verified the target (a business
/// profile, a region, a booking) belongs to the acting account — an
/// "Own only" cell in the matrix denies the action outright when this is
/// false or omitted, exactly like [Permission.suspendBanUserOrBusiness]
/// denying a Regional Admin acting outside their own region. The
/// ownership check itself (matching a business profile's owner_id, or a
/// region against assignedRegion) is NOT this function's job — it depends
/// on data (business profile ownership, regions) this phase doesn't build
/// yet; callers own resolving `isOwnResource` correctly once that data
/// exists.
bool hasPermission(
  Role role,
  Permission permission, {
  bool isOwnResource = false,
}) {
  final grant = _matrix[permission]?[role] ?? _Grant.no;
  return switch (grant) {
    _Grant.yes => true,
    _Grant.ownOnly => isOwnResource,
    _Grant.no => false,
  };
}

/// Human-readable label + display grouping for [Permission] — used only
/// by the admin Profiles detail page's "what this profile can do" list.
/// Purely presentational; [hasPermission]/[_matrix] above remain the only
/// real enforcement logic.
extension PermissionDisplay on Permission {
  String get label => switch (this) {
        Permission.browseSearchListings => 'Browse & search listings',
        Permission.bookHotelTourGuide => 'Book a hotel, tour, or guide',
        Permission.writeReviews => 'Write reviews',
        Permission.createEditOwnBusinessProfile =>
          'Create/edit a business profile',
        Permission.manageOwnBookingsCalendar => 'Manage bookings & calendar',
        Permission.approveRejectBusinessListings =>
          'Approve/reject business listings',
        Permission.verifyLicensesCertifications =>
          'Verify licenses & certifications',
        Permission.moderateReviewsContent => 'Moderate reviews & content',
        Permission.suspendBanUserOrBusiness =>
          'Suspend/ban a user or business',
        Permission.managePaymentsPayouts => 'Manage payments & payouts',
        Permission.viewPlatformAnalytics => 'View platform analytics',
        Permission.manageOtherAdminAccounts =>
          'Manage other admin accounts',
        Permission.assignChangeUserRoles => 'Assign/change user roles',
      };

  /// Display-only grouping for the profile detail page's by-area
  /// sections — not part of the matrix itself, doesn't affect
  /// [hasPermission].
  String get area => switch (this) {
        Permission.browseSearchListings ||
        Permission.bookHotelTourGuide ||
        Permission.writeReviews =>
          'Traveller actions',
        Permission.createEditOwnBusinessProfile ||
        Permission.manageOwnBookingsCalendar =>
          'Business & listings',
        Permission.approveRejectBusinessListings ||
        Permission.verifyLicensesCertifications ||
        Permission.moderateReviewsContent ||
        Permission.suspendBanUserOrBusiness =>
          'Moderation & trust & safety',
        Permission.managePaymentsPayouts ||
        Permission.viewPlatformAnalytics ||
        Permission.manageOtherAdminAccounts ||
        Permission.assignChangeUserRoles =>
          'Platform & admin',
      };
}

/// One permission [role] is actually granted, as shown on the Profiles
/// detail page. [ownOnly] means the grant is scoped to the account's own
/// resource (see [hasPermission]'s doc comment on `isOwnResource`), not a
/// blanket grant — the UI should visibly distinguish the two rather than
/// rendering every entry the same way.
class GrantedPermission {
  final Permission permission;
  final bool ownOnly;
  const GrantedPermission(this.permission, {required this.ownOnly});
}

/// Every permission [role] is actually granted (`yes` or `own only`),
/// in matrix declaration order — the Profiles detail page's single data
/// source for "what this profile can actually do." Denied (`no`) cells
/// are omitted entirely rather than listed as crossed-out/greyed, per the
/// explicit rule not to imply a permission the app doesn't enforce.
List<GrantedPermission> permissionsFor(Role role) {
  final result = <GrantedPermission>[];
  for (final permission in Permission.values) {
    final grant = _matrix[permission]?[role] ?? _Grant.no;
    if (grant == _Grant.no) continue;
    result.add(
      GrantedPermission(permission, ownOnly: grant == _Grant.ownOnly),
    );
  }
  return result;
}

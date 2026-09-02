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

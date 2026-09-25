import 'dart:ui' show Color;

/// The single, unambiguous role taxonomy for every account on the
/// platform — matches `public.user_role` (Postgres enum) exactly. Every
/// account has exactly one [Role] (stated directly in the source Roles &
/// Permissions matrix, and enforced by `profiles.role` being `not null`
/// with no array/multi-value type).
///
/// Resolves a real mismatch found across the source schema's sheets: the
/// Traveller sheet's own Role dropdown listed only 4 values (Traveller,
/// Business Owner, Guide, Admin) while the Roles & Permissions matrix
/// defines 6 with materially different permissions each (a Content
/// Moderator and a Super Admin are not interchangeable "Admin"). This enum
/// is the matrix's 6, plus [financeAdmin] — see the doc comment on
/// [AdminRoleTitle] in admin_profile.dart for why a 7th value was needed.
enum Role {
  traveler,
  guide,
  businessOwner,
  contentModerator,
  regionalAdmin,
  superAdmin,
  financeAdmin;

  /// Matches the `user_role` Postgres enum's labels exactly.
  String get wire => switch (this) {
        Role.traveler => 'traveler',
        Role.guide => 'guide',
        Role.businessOwner => 'business_owner',
        Role.contentModerator => 'content_moderator',
        Role.regionalAdmin => 'regional_admin',
        Role.superAdmin => 'super_admin',
        Role.financeAdmin => 'finance_admin',
      };

  /// Defaults to [Role.traveler] for a null/unrecognized value — matches
  /// `profiles.role`'s own `not null default 'traveler'` (every account
  /// really does have a role; a null here only means the caller hasn't
  /// loaded the profile row yet, not a genuinely roleless account).
  static Role fromWire(String? value) => switch (value) {
        'guide' => Role.guide,
        'business_owner' => Role.businessOwner,
        'content_moderator' => Role.contentModerator,
        'regional_admin' => Role.regionalAdmin,
        'super_admin' => Role.superAdmin,
        'finance_admin' => Role.financeAdmin,
        _ => Role.traveler,
      };

  /// Whether this role is one of the 3 admin tiers the source schema's
  /// Admin profile sheet covers (Content Moderator/Regional Admin/Super
  /// Admin) plus [financeAdmin] — i.e. whether an account with this role
  /// should have a row in `admin_profiles` rather than `traveller_profiles`.
  bool get isAdminTier => switch (this) {
        Role.contentModerator ||
        Role.regionalAdmin ||
        Role.superAdmin ||
        Role.financeAdmin =>
          true,
        _ => false,
      };

  /// Human-readable badge label — e.g. the profile panel's role pill.
  /// "Traveller" (double-l, matching the source schema's own spelling)
  /// rather than "Traveler" for that one specifically; every other label is
  /// just the title-cased wire value.
  String get label => switch (this) {
        Role.traveler => 'Traveller',
        Role.guide => 'Guide',
        Role.businessOwner => 'Business Owner',
        Role.contentModerator => 'Content Moderator',
        Role.regionalAdmin => 'Regional Admin',
        Role.superAdmin => 'Super Admin',
        Role.financeAdmin => 'Finance Admin',
      };

  /// Single source of truth for the role pill's tint — shared by the
  /// profile header's identity badge (profile_chrome.dart's `_Header`) and
  /// the admin Users/Profiles table's ROLE column (settings_tab.dart's
  /// `_UserRow`), so the two surfaces can't independently drift on what
  /// color a given role reads as. [isAdminTier] roles get a saturated,
  /// attention-grabbing hue (consumers additionally raise alpha/weight for
  /// these — see each call site); [Role.superAdmin] specifically reuses
  /// this screen's existing "critical" red accent (matches the sign-out
  /// icon / alert-severity color already on this surface) since it's the
  /// single most powerful tier. [Role.guide]/[Role.traveler] (and
  /// [Role.businessOwner], which carries no elevated platform privilege)
  /// stay in the surface's existing muted/teal/blue hues instead.
  Color get badgeColor => switch (this) {
        Role.superAdmin => const Color(0xFFEF5350),
        Role.financeAdmin ||
        Role.regionalAdmin ||
        Role.contentModerator =>
          const Color(0xFFD4A017),
        Role.businessOwner => const Color(0xFF5B8DEF),
        Role.guide => const Color(0xFF12A594),
        Role.traveler => const Color(0xFF9A9A9A),
      };

  /// Fixed display order for the admin Profiles list, most-privileged
  /// first (Salesforce's own Setup → Profiles page reads the same way) —
  /// deliberately NOT the enum's declaration order above, which groups
  /// traveller-facing roles first for unrelated historical reasons.
  static const List<Role> byPrivilege = [
    Role.superAdmin,
    Role.financeAdmin,
    Role.regionalAdmin,
    Role.contentModerator,
    Role.businessOwner,
    Role.guide,
    Role.traveler,
  ];

  /// This role's profile "Type", Salesforce-style. Every [Role] is
  /// [ProfileType.standard] today — the app has no data-driven mechanism
  /// for defining a genuinely new, custom permission set (permissions are
  /// a fixed matrix in `permissions.dart` keyed on this fixed 7-value
  /// enum, not rows in a table). Building that is a real, separate,
  /// larger project (turning the matrix into data and `profiles.role`
  /// into a foreign key touching every RLS policy that checks it) —
  /// explicitly out of scope this phase; the admin Profiles list has no
  /// "New Profile" action as a result. Kept as an enum rather than a bare
  /// `true`/"Standard" literal so that future project has somewhere to
  /// plug in [ProfileType.custom] without a breaking change here.
  ProfileType get profileType => ProfileType.standard;

  /// Short, factual summary of what this role can actually do — each
  /// sentence is a direct restatement of that role's granted (`yes`/`own
  /// only`) cells in `permissions.dart`'s matrix, nothing invented or
  /// implied beyond it. Shown as the admin Profiles list's Description
  /// column and the profile detail page's header. See
  /// `permissionsFor(role)` in permissions.dart for the structured,
  /// grouped version of the same data.
  String get description => switch (this) {
        Role.traveler =>
          'Browse & search listings, book hotels/tours/guides, and write reviews.',
        Role.guide =>
          'Browse listings, write reviews, and manage their own guide profile and bookings calendar.',
        Role.businessOwner =>
          'Browse listings and manage their own business profile and bookings calendar.',
        Role.contentModerator =>
          'Browse listings, approve or reject business listings, verify licenses for their own cases, moderate reviews/content, and view analytics for their own scope.',
        Role.regionalAdmin =>
          'Browse listings, approve or reject business listings, verify licenses platform-wide, moderate reviews/content, and — within their own region — suspend/ban accounts, manage payments/payouts, and view analytics.',
        Role.superAdmin =>
          'Full platform access: every business, moderation, payments, analytics, and admin-management permission, including managing other admin accounts and assigning roles.',
        Role.financeAdmin =>
          'Browse listings, plus manage payments/payouts and view analytics for their own accounts — no other admin permissions.',
      };
}

/// Salesforce-style profile "Type" — see [Role.profileType]'s doc comment
/// for why every profile is [standard] today and what it would take to
/// support [custom].
enum ProfileType {
  standard,
  custom;

  String get label => switch (this) {
        ProfileType.standard => 'Standard',
        ProfileType.custom => 'Custom',
      };
}

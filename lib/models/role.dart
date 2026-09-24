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
}

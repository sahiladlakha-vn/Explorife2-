# Roles & Permissions Foundation — Phase 1

Scope: `Role` enum, permission enforcement, `Traveller` profile, `Admin` profile.
Explicitly out of scope: the 8 business profile types (Hotel, Tour Operator, Guide,
Transportation, Restaurant, Attraction, Wellness, Retail) — all depend on `Role`
being correct first.

## Prerequisite findings (before any design work)

- **Real auth already exists.** Supabase Auth, real sessions, real `auth.uid()`-scoped
  RLS across the schema (`saved_gems`, `trip_bookings`, `hike_tracks`, etc.). Not a
  stub — this phase extends it, it doesn't build auth from zero.
- **Login is OAuth-only: Google and GitHub.** No email/password flow exists, and no
  Facebook/Apple sign-in exists. The source schema's `loginMethod` field lists
  Email/Google/Facebook/Apple — 3 of those 4 have no working sign-in behind them.
  Resolved (with product): `LoginMethod` reflects reality only —
  `{google, github}` — not the aspirational list. See `lib/models/traveller_profile.dart`.
- **Password is not this app's concern.** Supabase Auth owns credentials entirely
  in `auth.users`; nothing in this phase touches or duplicates password storage.
  The schema's "hashed, never plain text" instruction is best satisfied by not
  building a parallel password field at all.
- **A live, production role system already existed and nothing in the task
  description accounted for it.** `profiles.role` is a real Postgres enum
  (`user_role`) with 13 real rows already assigned (`admin`, `guide`, `traveler`)
  before this phase started. Confirmed via a repo-wide grep that **no Dart code
  reads this column** — but 3 real RLS policies on `stories` did
  (`stories_select_admin`/`update_admin`/`delete_admin`, each checking
  `profiles.role = 'admin'`), found only when the first migration attempt failed
  on a dependency error. Those three policies were dropped and recreated against
  the new enum with the corrected predicate (`content_moderator`, `regional_admin`,
  `super_admin` — matching the matrix's "Moderate reviews/content" row, not just
  the collapsed old `admin` value).

## Open Decision 1 — the Role enum mismatch

**Resolved: `Role` is a 7-value enum**, matching the real "Roles & Permissions" sheet's
6 roles (`traveler, guide, business_owner, content_moderator, regional_admin,
super_admin`) plus `finance_admin` (see Decision 2). The Traveller sheet's 4-value
dropdown (Traveller, Business Owner, Guide, Admin) is the oversimplification —
`Admin` collapses 3 permission tiers the matrix defines separately with different
rights. `Role` is the single enum used everywhere: `profiles.role` (Postgres enum,
recreated), `AuthUser.role`/`AuthProvider.role` (Dart), and the only thing
`hasPermission()` keys on.

Note the source spreadsheet in Downloads existed as two files — the un-suffixed
copy was missing the "Roles & Permissions" sheet entirely; the `(1)` copy has it.
That copy was treated as ground truth throughout.

## Open Decision 2 — Support Staff / Finance Admin have no defined permissions

The Admin sheet's "Role / Title" dropdown has 5 values; the matrix only ever
defined 3 columns. Resolved (with product):

- **Support Staff → shares Content Moderator's permission tier exactly.** No new
  `Role` value — `AdminRoleTitle.supportStaff.permissionRole == Role.contentModerator`.
  Two admins can carry different `role_title` labels (one `support_staff`, one
  `content_moderator`) while getting identical permissions.
- **Finance Admin → a new, narrower tier.** Added `Role.financeAdmin` to the
  enum and one new row to the matrix: browse & search (yes, like everyone),
  manage payments/payouts (own only), view platform-wide analytics (own only),
  everything else denied — including approve/reject listings, moderate content,
  suspend/ban, and manage other admins. This is the narrowest admin tier in the
  matrix by design; a finance role has no business moderating content or banning
  accounts.

`AdminRoleTitle` (5 values, `admin_profiles.role_title`) stays a separate,
more granular *display/audit* label from `Role` (7 values, `profiles.role`,
the actual enforcement key) — see `lib/models/admin_profile.dart`'s doc comment
for why two fields exist instead of one.

## Open Decision 3 — one Role per account

**Confirmed as a hard constraint, not actually open** — the source "Roles &
Permissions" sheet states it directly in its own text: *"Every account has exactly
one Role."* `profiles.role` is `not null`, single-value (not an array), enforcing
this at the schema level. A real guide who also wants to book trips as a
traveller needs a second, separate account under this design (their Guide
account keeps `Role.guide`, permission matrix row "Book hotel/tour/guide" = No
for Guide — this is the matrix's own stated behavior, not a gap introduced here).
This is worth revisiting once a real dual-identity need shows up in practice, but
nothing in this phase should quietly build around a different assumption.

## What was built

- `lib/models/role.dart` — the `Role` enum.
- `lib/core/auth/permissions.dart` — `Permission` enum (13 actions, one per
  matrix row) + the full matrix + `hasPermission(role, permission, {isOwnResource})`.
  Fully unit-tested against the real sheet data cell-by-cell
  (`test/core/auth/permissions_test.dart`, 78 matrix cells + finance-admin tier).
- `lib/models/traveller_profile.dart` + `lib/repositories/traveller_profile_repository.dart`
  — backed by new table `public.traveller_profiles` (migration `20260903000100`).
- `lib/models/admin_profile.dart` + `lib/repositories/admin_profile_repository.dart`
  — backed by new table `public.admin_profiles` (migration `20260903000200`).
- `lib/models/admin_action_log_entry.dart` + `lib/repositories/admin_action_log_repository.dart`
  — backed by new table `public.admin_action_log` (migration `20260903000300`), a
  real working write/read/count path with no caller yet (see below).
- `supabase/migrations/20260903000000_recreate_user_role_enum.sql` — clean
  recreation of the `user_role` Postgres enum (not `ALTER TYPE ADD VALUE`):
  13 existing rows migrated (`admin → super_admin`, `guide`/`traveler` unchanged),
  the 3 dependent `stories` RLS policies dropped and recreated against the new
  values. Verified live: `select role, count(*) from profiles group by role`
  returns `traveler: 6, guide: 6, super_admin: 1` post-migration.
- `AuthProvider`/`AuthUser` extended with `role: Role`, loaded from `profiles.role`
  alongside the existing display_name/avatar_url/username select. Admin-tier
  sign-ins record `last_login`/`last_login_ip` on `admin_profiles` (IP via a
  client-side lookup to api.ipify.org — a Flutter client has no other way to
  learn its own public IP; this is an honest audit nicety, not a server-verified
  capture, and never blocks or fails sign-in on error).

## Fields deliberately NOT built (with reasoning)

- **`loyaltyPoints`** — no loyalty program exists or is planned anywhere in this
  app. Omitted per the task's own instruction to skip dead functionality.
- **`paymentMethods`** — no payment provider has been chosen (this app has no
  real booking/payment backend at all — see Tour's own doc comment). Tokenizing
  against a provider that doesn't exist would be a field that looks real but
  isn't.
- **`reviewsWritten`** — this app has no reviews/ratings feature anywhere (Gems
  have none; Tour explicitly deferred them for the same no-payment-backend
  reason). `TravellerProfileRepository.fetchReviewsWritten` returns an honest
  empty list rather than fabricating a reviews table this phase was never asked
  to build.
- **Real 2FA** — `admin_profiles.two_factor_enabled` is stored, but not backed by
  any MFA enrollment/verification flow. Any UI for it must say "Coming soon,"
  never present as a working toggle.
- **`permissionLevel`** (Admin sheet's own multi-select) — not a stored column.
  It's computed from the account's `Role` via the permission matrix, so there is
  exactly one source of truth for what an admin can do, not a second field that
  could silently drift from it.
- **`profilesApproved`/`disputesHandled`** — not stored counters. Computed by
  counting `admin_action_log`, so they can never drift from the log they
  summarize. Both correctly return 0 today: no admin-action UI exists anywhere
  in this app yet (every real action in the matrix — approve a listing, verify a
  license, moderate content — depends on the 8 business profile types or a
  content/reviews system, both out of scope this phase).

## `wishlist` — explicit decision

Reuses the **existing** gem-save mechanism end-to-end
(`gem_saves`/`GemProvider.toggleSave`/`GemRepository.fetchSavedGems`) rather than
a second, parallel saved-items table. `TravellerProfileRepository.fetchWishlist`
delegates directly to `GemRepository().fetchSavedGems()` — not a reimplementation
of the same join, so there's no way for the two to drift apart. In-app UI should
keep using `GemProvider.savedGems` directly (already reactive); the repository
method exists only so "where does wishlist data actually live" has one
documented answer.

## Verified live

- Migration applied cleanly against production Supabase; `profiles.role` data
  migration confirmed correct for all 13 existing rows.
- Real `traveller_profiles` row inserted end-to-end for an existing traveler
  account — every field (nationality, login_method, travel_style, budget_range,
  interests array, verification_status) round-tripped correctly.
- Real `admin_profiles` row inserted for the existing super-admin account —
  role_title, managed_profile_types, account_status all correct.
- Real `admin_action_log` entry inserted and read back successfully — the write
  path this phase's "no caller yet" note depends on being real, not theoretical.
- 336 tests pass project-wide (110 new: full 78-cell matrix verification +
  finance-admin tier + Role/AdminProfile/TravellerProfile model round-trips),
  `flutter analyze` clean (same 38 pre-existing infos, nothing new introduced).

# Attraction — First of 8 Business Profile Types

First of 8 business types (Hotel, Tour Operator, Guide, Transportation, Restaurant,
Attraction, Wellness, Retail) being built one at a time. This sets the pattern the
remaining 7 will follow, especially any with similarly overlapping curated content.

## Prerequisite check

Confirmed live before starting: `Role` enum, `hasPermission()`, `traveller_profiles`/
`admin_profiles` tables, `profiles.role` migrated to the 7-value enum (see
`docs/audits/roles-permissions-foundation-2026-09-03.md`).

## Decision 1 — Gem/Attraction relationship

**Resolved: Attraction links to an existing Gem when matched, per option 2.**
`attractions.gem_id` is a nullable FK to `saved_gems.id`. At listing-creation time,
`findLikelyGemMatch()` (`lib/core/services/poi_dedup.dart`) checks the new
listing's name+coordinates against every existing Gem using the SAME proximity
(30m) + fuzzy-name matching already built for Tilequery/Gem dedup — not a new,
separate matching rule. A match surfaces as a confirm-or-decline dialog
("This looks like an existing place — link it?"), never an automatic silent link.
An Admin implicitly re-confirms this during verification by seeing the "LINKED TO
GEM" badge on the moderation queue card.

A Gem's own curated content (description, photos) is **never replaced or merged**
when linked — Gem Detail shows exactly what it shows today. A verified linked
Attraction surfaces as a new, visually distinct "VERIFIED BUSINESS LISTING" card
(entry fee, hours, recommended duration, a link to the full listing) appended
*after* the existing accordion, never inside it. An Attraction with `gem_id = null`
is a genuinely new place with no prior curated entry, browsable at its own
`/attractions/:id` route.

## Decision 2 — category taxonomy

**Resolved: Attraction reuses Gem's existing 10-category taxonomy exactly**
(`hiking, camping, viewpoint, food, temple, cave, coastal, nature, heritage,
landmark`) — enforced by the same CHECK constraint list as `saved_gems.category`
and `tours.category` before it. The source schema's own 5-value list (Museum, Park,
Historical Site, Adventure Activity, Theme Park) is NOT used. Rationale: once a Gem
and an Attraction can be the same real place, having two different category systems
for that one place was judged a bigger problem than schema literalism. Suggested
mapping for anyone entering data: Museum/Historical Site -> `heritage`, Park ->
`nature`, Theme Park -> `landmark` (closest fit — no dedicated category exists),
Adventure Activity -> `hiking` (closest fit). This is the SAME "one shared taxonomy"
principle Tour already follows for its own `category` field.

## What was built

- `supabase/migrations/20260904000000_create_attractions.sql` — `attractions`
  table, RLS (public sees verified only; owners see their own regardless of
  status; admin-tier roles see everything), a trigger that silently reverts
  `verification_status`/`verified_by`/`verified_at` to their prior value on any
  update from a non-admin (so an owner's own UPDATE policy can't be used to
  self-verify, regardless of what a client sends), and the `verify_attraction`
  RPC — the sanctioned approve/reject path, security-definer, checks the caller
  is Content Moderator/Regional Admin/Super Admin, updates the row, AND writes a
  real `admin_action_log` entry in the same transaction. This is
  `admin_action_log`'s **first real caller** (built in the Role foundation phase
  with none yet).
- `lib/models/attraction.dart`, `lib/repositories/attraction_repository.dart`.
- `lib/screens/attractions/attraction_form_screen.dart` — Business Owner create/
  edit. Checks `AuthProvider.role == Role.businessOwner` before showing the form
  (RLS is the real gate; this is the fast, honest denial instead of letting a
  non-owner fill out the whole form only to hit a silent RLS rejection at
  submit). Reuses the existing photo-upload mechanism (`GemRepository.
  uploadPhotos`, the same Storage bucket/policies Drop-a-Gem already uses) and
  the existing `GeocodingService` for address -> coordinates — no new upload
  infra, no new geocoding path.
- `lib/screens/attractions/attraction_moderation_screen.dart` — the "Approve/
  reject business listings" queue, gated on `role.isAdminTier`.
- `lib/screens/attractions/attraction_detail_screen.dart` — standalone public
  view for an unlinked Attraction (or reached directly from Gem Detail's "View
  full listing" link for a linked one). Reuses `PhotoCarousel` (the same shared
  hero component Gem Detail/Tour Detail already use) — no third gallery widget.
- `lib/screens/gems/gem_detail_screen.dart` — extended with `_AttractionInfoCard`,
  fetched via `AttractionRepository.fetchVerifiedForGem` and shown only when a
  verified linked listing exists. Zero change to existing accordion behavior.
- `lib/core/services/poi_dedup.dart` — generalized `sameRealPlace` into
  `placeLikelyMatchesGem` (plain name/lat/lng params instead of being tied to
  `NearbyPoi`) plus a new `findLikelyGemMatch` helper, so Attraction's "is this an
  existing place" check and Destination Detail's Tilequery-dedup check share one
  matching rule instead of two.

## What was NOT built (with reasoning)

- **Certification file-upload UI** — the `certification_urls` column exists
  (real, working schema field), but no upload UI for it this phase. Same
  "field exists, no authoring UI yet" convention this app already uses elsewhere
  (e.g. `curated_collections.dart` before it has a real CMS) — an admin can
  populate it directly until a real UI is worth building.
- **Rating/reviews** — deliberately absent, not fabricated. This app has no
  reviews/ratings feature anywhere (Gems have none; Tour explicitly deferred
  reviews for the same reason: no real bookings to source them from). Nothing
  in Attraction invents a parallel review system.
- **A full "Attractions" browse rail / search-tab integration** (the way Tours
  got a Home rail + a 3rd search tab) — not asked for this round; the standalone
  detail screen exists and is reachable (direct route + from a linked Gem's
  "View full listing" link), but there's no dedicated Attraction-browsing entry
  point yet. Revisit once more business types exist and a consistent "business
  discovery" pattern is worth designing once, not per-type.

## Verified live, end-to-end (real Supabase, not assumed)

Using two of the app's existing seeded test accounts (temporarily set to
`business_owner`, reverted after) and the real `super_admin` account:

1. Owner1 inserts an Attraction — succeeds, defaults to `pending`.
2. Owner2 attempts to update Owner1's listing — **silently blocked** (0 rows
   affected), confirming "own only" enforcement.
3. Owner1 updates their own listing — succeeds.
4. Owner1 (non-admin) attempts to directly set `verification_status = 'verified'`
   — the trigger **silently reverts it**; the row stays `pending`.
5. The real Super Admin calls `verify_attraction(..., true)` — the row becomes
   `verified` with `verified_by`/`verified_at` set, AND a real row lands in
   `admin_action_log` (`action_type = 'approve_listing'`).
6. A non-admin (Owner2) calling `verify_attraction` directly — **rejected** with
   the RPC's own exception, not silently allowed.

All test data cleaned up afterward; the two seed accounts reverted to their
original `guide` role. 341 tests pass project-wide (5 new Attraction model
tests), `flutter analyze` clean (3 new info-level lints matching an existing
codebase-wide pattern, no new warnings/errors).

## Post-review fixes (2026-09-04)

Code review of this phase surfaced one real bug and one real gap, both fixed
before starting the next business type.

### Fix 1 — `placeNamesLikelyMatch`'s overlap fallback had no minimum-word guard

The whole-word-containment branch was guarded to `smallerWords.length >= 2`
(per its own comment: naive matching let "Park" match "Parking Garage"), but
the final overlap-ratio fallback had no equivalent guard. When the smaller
name normalizes to a single word, `overlap/smaller` is always either 0 or
1.0/1 = 1.0 — so ANY single shared word matched, regardless of context. A Gem
named e.g. "Coffee" would match the real "Highlands Coffee" cafe (from this
file's own Hoan Kiem Tilequery pull) as if they were the same place.

**Fixed** by gating the smaller-name word count once, before either branch
runs (`if (smallerWords.length < 2) return false;`) — a single-word name can
now only match via an EXACT normalized match (already handled separately),
never a partial one. Confirmed this doesn't regress the "Sapa" == "Sapa"
case (still caught by the exact-match check, unaffected) or genuine 2+-word
partial matches (still caught by the fallback once both names have >=2
words). Four new tests added to `test/core/services/poi_dedup_test.dart`
covering exactly this: the fixed false-positive, the pre-existing "Park"
case, the exact single-word match, and a genuine 2+-word overlap.

### Fix 2 — no DELETE policy existed on `attractions`

Confirmed NOT intentional. **Resolved as soft-delete**, not a hard DELETE
policy — see `supabase/migrations/20260904000100_add_attraction_soft_delete.sql`:

- New `deleted_at timestamptz` column.
- A new `retract_attraction(p_attraction_id)` RPC: the listing's own owner
  (any time, any verification status — a closed business shouldn't need an
  admin's permission to stop advertising itself) or an admin-tier account
  (moderation power) may retract a listing. Only the admin-driven path
  writes to `admin_action_log` (a new `retract_listing` action type) — an
  owner retracting their own listing isn't an "admin action" in the sense
  that table exists to track, and since an account can't hold both a
  `business_owner` and an admin-tier role at once (Role foundation's
  "exactly one Role" rule), the two paths never overlap for the same caller.
- The public-feed SELECT policy now also excludes `deleted_at is null` —
  a retracted listing stops appearing to travellers immediately. Owners and
  admins keep seeing retracted listings in their own broader read policies
  (unchanged), so an owner can still see their own past/retracted listings.
- Rationale for soft- over hard-delete: matches this app's own established
  convention (every account-status field in this schema — traveller/admin
  profiles alike — is a status flag, never a row deletion), and keeps a
  real row `admin_action_log` can reference for a retraction the same way
  it already does for approvals/rejections. A hard-deleted row can't be
  logged against after the fact.
- A minimal "Retract listing" action was added to the owner's own
  `AttractionDetailScreen` view (with a confirm dialog and a "RETRACTED"
  badge once retracted); no separate admin-side retraction UI was built
  this round (the repository/RPC layer is real and tested; a full
  admin "manage all listings" screen wasn't asked for yet).

**Verified live, end-to-end** (same real-account pattern as the original
verification tests): an owner retracted their own verified listing — it
correctly disappeared from the public-feed query while keeping
`verification_status = 'verified'` intact, and generated **zero** new
`admin_action_log` rows. A second listing retracted by the real Super Admin
correctly generated a `retract_listing` log entry. All test data cleaned up
afterward.

This DELETE-policy question will very likely recur for Restaurant (the next
business type) — the same soft-delete pattern (a `deleted_at` column + an
owner-or-admin RPC that only logs the admin path) should be reused rather
than re-decided from scratch.

# Restaurant — Second of 8 Business Profile Types

Second of 8 business types, built directly on the pattern Attraction (see
`docs/audits/attraction-business-profile-2026-09-04.md`) established:
Gem-linking via `gem_id`, verification via RLS + a field-lock trigger + a
`verify_*` RPC, soft-delete via `deleted_at` + a `retract_*` RPC. None of
that was re-decided here — see "What was reused unchanged" below.

## Prerequisite check

Confirmed before starting: the Attraction implementation (including the
`deleted_at`/retraction audit fix and the `placeNamesLikelyMatch` fix) is
merged to `main` and deployed to production (`explorife2.vercel.app`,
verified live). `poi_dedup.dart`'s `findLikelyGemMatch`/`placeLikelyMatchesGem`
are the same functions this phase's Gem-linking reuses directly.

## What was reused unchanged

- RLS shape: public sees verified + not-deleted only; owners see their own
  regardless of status; admin-tier (`content_moderator`, `regional_admin`,
  `super_admin`) sees everything.
- The verification-field-lock trigger (`lock_restaurant_verification_fields`)
  — same shape as `lock_attraction_verification_fields`, table name swapped.
- `verify_restaurant`/`retract_restaurant` RPCs — same shape as
  `verify_attraction`/`retract_attraction`, reusing the SAME
  `admin_action_log` action types (`approve_listing`/`reject_listing`/
  `retract_listing`) rather than adding business-type-specific ones, since
  those are already generic across every business type.
- Gem-linking at listing-creation time via `findLikelyGemMatch` — the exact
  same function Attraction uses, no new matching logic.
- Soft-delete via `deleted_at` — applied from this table's creation, not
  retrofitted.

## What's actually different here (the real open decisions)

### (a) Menu Highlights storage — a linked table, not JSON

**Decision: `restaurant_menu_items`, a real table, one row per dish** (id,
restaurant_id, dish_name, price_amount, currency, photo_url, display_order).

**Trade-off, stated explicitly rather than decided silently:**
- *For a linked table*: consistent with how every other multi-item concept
  in this app is modeled (`saved_gems`, `tours`, `attractions` — never a
  JSON blob column); per-dish photos are one plain column instead of a
  nested array-of-objects shape; a future "search by dish" feature can
  query `restaurant_menu_items` directly with zero schema changes.
- *For a JSON column*: would have shipped faster (no second table, no
  second repository surface, no second RLS policy set — `restaurant_menu_items`
  needed 3 SELECT policies + 1 ALL policy of its own, see the migration).
- **Chosen the table** — the "search by dish" non-goal was explicit in the
  prompt as something not to foreclose, and a JSON column would need a full
  rewrite to support it later, while the table already does.

RLS on `restaurant_menu_items` mirrors the parent restaurant's own read
policies (a menu item is only public when its restaurant is verified +
not-retracted; owner/admin see their own/all regardless) rather than
carrying an independent `verification_status` — see point (d) below.

### (b) Reservation Option — informational only, confirmed

**Decision: informational only.** `reservation_option` is a plain boolean
rendered as "Reservations accepted" / "Walk-ins only" on the Restaurant
detail screen and on the Gem Detail linked-business card — never a booking
action, never a "Reserve now" button. Same reasoning Tour's "Check
availability" was deferred for: no real reservation backend exists to book
against, so a button implying one would be a dead end. This was the
prompt's own stated default ("unless told otherwise") and nothing in this
phase's scope calls for building a real reservation flow, so no
confirmation round-trip was needed beyond stating the decision here.

### (c) `ratingReviews` — deliberately NOT built (not merely deferred)

The source data model lists `ratingReviews` as "auto-calculated," but this
app has no reviews/ratings mechanism anywhere to calculate it from — Gems
have none, Tour explicitly deferred it, Attraction explicitly left it out,
all for the same reason (no real bookings/visits to source reviews from).
Adding a fabricated rating field with nothing real behind it would be
worse than omitting it. There is no `rating`/`review_count` column on
`restaurants`, and no UI implies one exists. Revisit only if/when a real
review system is built for every listing type at once — not per business
type.

### (d) Business License — same convention as Attraction's `certification_urls`, confirmed

One `verification_status` covers the whole listing, including the
license — there is no separate per-field license-verification status,
matching Attraction's actual pattern exactly (confirmed by re-reading
`attractions`' migration and `AttractionFormScreen` before building this).
`business_license_url` is a single nullable text column (not an array,
unlike Attraction's `certification_urls` — the source schema describes
ONE license per restaurant) with no authoring UI this phase, same "field
exists, no upload UI yet" convention Attraction already established (an
admin can populate it directly).

### (e) Gem Detail linked-business card — generalized this round

**Decision: generalized now, not deferred to the third business type.**
`lib/widgets/gems/linked_business_card.dart` — a public `LinkedBusinessCard`
(badge + ordered info rows + "View full listing" link) and
`LinkedBusinessInfoRow` — replaces Attraction's original private
`_AttractionInfoCard`, which was refactored onto the shared widget in the
same change (its Gem Detail behavior is pixel-identical; only the
implementation moved). Restaurant's own linked card is built the same way.
Chosen because with an 8-type roadmap, every additional business type
would otherwise duplicate the badge/rows/link shell Attraction already
proved out — the second occurrence of an identical pattern was judged the
right point to generalize, not the third.

`GemDetailScreen._load()` now fetches a linked Attraction AND a linked
Restaurant in parallel (`Future.wait`) and can show both cards at once — a
real place (e.g. a heritage site with an on-site restaurant) can
legitimately have a verified listing under more than one business type.

## Proactive `deleted_at`/retraction audit (not deferred to a second pass)

Attraction only got its `deleted_at`/`verification_status` gap fix after a
dedicated second review pass (see that audit doc's "Post-review fix 2").
Applied here from the start instead:

- `fetchVerified`, `fetchVerifiedForGem`: query-level `.filter('deleted_at',
  'is', null)` AND results piped through `liveVerifiedRestaurant()` — the
  same top-level pure client-side backstop function
  (`lib/repositories/restaurant_repository.dart`) Attraction's fix added.
- `fetchPending`: `.filter('deleted_at', 'is', null)` from the start — this
  is the exact bug Attraction's audit found (a listing retracted while
  still pending kept showing in the moderation queue); verified live below
  that it doesn't recur here.
- `fetchById`/`fetchOwnedByCurrentUser`: intentionally unfiltered, same
  reasoning as Attraction (the owner needs to see their own listing
  regardless of status) — documented in the repository method's own doc
  comment, not silently identical by omission.
- The RETRACTED badge on `RestaurantDetailScreen` is visible to
  `isOwner || auth.role.isAdminTier` from the start — Attraction's badge
  fix, applied here as the initial implementation rather than a follow-up.

## Verified live, end-to-end (real Supabase, real accounts)

Using two of the app's seeded `guide` test accounts (temporarily set to
`business_owner`, reverted after) and the real `super_admin` account —
same pattern as Attraction's own verification:

1. Owner1 inserts a Restaurant — succeeds, defaults to `pending`.
2. Owner2 attempts to update Owner1's listing — silently blocked (name
   unchanged, confirmed via a superuser read), confirming "own only"
   enforcement.
3. Owner1 updates their own listing — succeeds.
4. Owner1 (non-admin) attempts to directly set `verification_status =
   'verified'` — the trigger silently reverts it; the row stays `pending`.
5. The real Super Admin calls `verify_restaurant(..., true)` — the row
   becomes `verified` with `verified_by`/`verified_at` set, AND a real row
   lands in `admin_action_log` (`action_type = 'approve_listing'`).
6. Owner2 (non-admin) calling `verify_restaurant` directly — rejected with
   the RPC's own exception, not silently allowed.
7. `restaurant_menu_items` RLS: Owner1 adds a dish to their own restaurant
   — succeeds. Owner2 attempts to insert a dish into Owner1's restaurant —
   rejected (RLS policy violation, not silently ignored). Once the
   restaurant is verified, an anonymous session can read its menu items.
8. Owner1 retracts their own verified listing via `retract_restaurant` —
   `verification_status` stays `'verified'` (the exact gap Attraction's
   fix targeted) while `deleted_at` is set, and generates **zero**
   `admin_action_log` rows. Re-running the `fetchVerifiedForGem`-shaped
   query (`verification_status = 'verified' and deleted_at is null`) as
   owner, the real Super Admin, and anon all correctly return **zero**
   rows.
9. A fresh `pending` listing, withdrawn via `retract_restaurant` by its
   owner while still pending: the naive moderation-queue query
   (`verification_status = 'pending'`, no `deleted_at` filter) would have
   returned it (count 1); the fixed `fetchPending`-shaped query (`... and
   deleted_at is null`) correctly excludes it (count 0) — confirms the
   Attraction `fetchPending` bug does not recur here.
10. A separate listing retracted by the real Super Admin (not its own)
    correctly generated a `retract_listing` `admin_action_log` entry.

All test data (3 restaurants, 1 menu item, 3 admin_action_log rows) cleaned
up afterward; both seed accounts reverted to their original `guide` role.

361 tests pass project-wide (12 new: 8 `Restaurant`/`RestaurantMenuItem`
model tests, 4 `liveVerifiedRestaurant` tests). `flutter analyze`: 44
issues, all info-level — 41 pre-existing plus 3 new `use_build_context_synchronously`
infos in `RestaurantFormScreen._submit`, which are the exact same
pre-existing pattern already present (and already accepted) in
`AttractionFormScreen._submit`, not a new category of issue.

## What was NOT built (same reasoning as Attraction)

- **No rating/reviews** — see decision (c) above.
- **No Business License upload UI** — see decision (d) above.
- **No dedicated Restaurant browse rail / search-tab integration** — same
  as Attraction: not asked for this round. The standalone detail screen is
  reachable via a direct route and from a linked Gem's "View full listing"
  link, same as Attraction; no separate discovery entry point yet.
- **No real reservation backend** — see decision (b) above.

## Next up

Guide, Hotel, or any other remaining business type were explicitly NOT
started this round, per the prompt's own sequencing note — this phase is
scoped to Restaurant only, verified end-to-end, same "one type at a time,
confirmed working before the next" discipline Attraction established.

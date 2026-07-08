# Explorife working-tree triage map — 2026-07-04 (for fresh-eyes session)

> **STATUS UPDATE 2026-07-06 — EXECUTED (verified against git 2026-07-07).** The triage
> below was carried out. The whole composite was committed in 10 dependency-ordered
> commits (`35cf2f0` → `e74eedc`, atop pre-existing `d0e7acc`/`c5db0a8`):
> - **Bug 1 (auth-race)** wiring committed in `b1301b0` (`main.dart` proxy rebuilds on
>   default→resolved userId transition; router-race fix; SplitsProvider registration).
> - **Bug 2 (stale-context)** fix committed in `8d52528` (`trip_setup_sheet.dart`
>   `_onComplete` captures `GoRouter`/`Navigator`/`ScaffoldMessenger` before the await;
>   `navigator.pop()` + `router.push(...)`). `flutter analyze` on that file: clean.
> - `flutter build web --release`: **green** (exit 0).
> - **STOPPED before deploy** — Sahil runs the local smoke test + `./deploy.sh` himself.
>
> **Remaining / NOT done:** (1) the **3 SQL migrations** are still uncommitted —
> `20260618000000_add_tagline_to_saved_gems.sql`, `20260618000100_create_gem_saves.sql`,
> `20260704000000_add_user_id_to_hike_tracks.sql` (note
> `20260630000000_create_trip_builder.sql` was already committed in `d0e7acc` and per the
> deployment memory was applied to prod 2026-07-03). (2) the deploy decision.
>
> **SCHEMA PROBE 2026-07-07 — all 3 uncommitted migrations are ALREADY LIVE in prod.**
> Verified via REST probes (calibrated: bad column → 400/42703, bad table → 404/PGRST205,
> so a 200 proves presence):
> - `saved_gems?select=tagline` → `200 [{"tagline":null}]` (column live)
> - `gem_saves?limit=1` → `200 []` (table live, not PGRST205)
> - `hike_tracks?select=user_id` → `200 []` (column live)
>
> So the 3 files are untracked RECORDS of schema already applied to prod, NOT a pending
> schema-half. Pre-deploy SQL step is a **no-op** — no `db push` needed before shipping the
> frontend. Frontend will NOT 400/404 for tagline / gem_saves / hike_tracks.user_id reasons.
> The files should still be COMMITTED so tracked history matches live prod (prod schema is
> currently ahead of the repo's tracked migrations) — record-keeping, not a deploy blocker.
>
> **Correction to any "drift" claims:** SplitsProvider was NOT reverted — it is committed
> in `042c2ae`, present, and still referenced by `hike_provider.dart`. There was no SQL
> rename. `feed_metrics_test` is committed (in `e74eedc`). Workstream 5 below is accurate
> as written.
>
> The original 2026-07-04 pre-execution analysis is preserved verbatim below as the
> historical record.

---

Starting point for tomorrow's triage. Prod is UNCHANGED tonight — nothing committed,
nothing deployed. Trip Builder is dark in prod (deployed bundle sends `owner_id: ""`
→ Supabase 400 `22P02 invalid input syntax for type uuid`).

Decision made tonight: **DEFER everything to a dedicated triage session.** There is no
partial commit that makes prod better — neither `main.dart` nor `app_router.dart`
compiles against HEAD standalone, so it's ship-the-whole-composite or ship-nothing.

## The composite = FIVE intermingled workstreams

1. **Trip Builder feature** (~2,500+ lines, all untracked)
   - `lib/screens/trip_setup/` — `trip_setup_sheet.dart`, `step_one_init.dart`, `step_two_template.dart`
   - `lib/screens/trip_builder/` — `trip_builder_screen.dart` (381), `widgets/itinerary_canvas.dart` (874),
     `widgets/summary_sidebar.dart` (699), `widgets/discovery_panel.dart` (361),
     `widgets/asset_card.dart` (165), `asset_data.dart` (21)
   - `lib/providers/trip_provider.dart`, `lib/routes/trip_routes.dart`, `lib/models/gem_draft.dart`
   - Migrations already committed (c5db0a8, d0e7acc) — provider/screens are the uncommitted half.

2. **SplitsProvider extraction refactor** (LOAD-BEARING, 5 files — NOT an inert registration)
   - `lib/providers/splits_provider.dart` (untracked, 130 lines, complete — methods moved OFF HikeProvider)
   - Consumed by (all MODIFIED, tracked): `lib/providers/hike_provider.dart`,
     `lib/screens/profile/profile_screen.dart`, `lib/screens/splits/splits_screen.dart`,
     `lib/screens/splits/split_detail_screen.dart`
   - Registering the provider in main.dart WITHOUT these screen edits (or vice-versa) breaks Splits.

3. **Gem-placement refactor** (fused into the router file)
   - `add_gem_screen.dart` (deleted) → `lib/screens/gems/placement_screen.dart` (untracked)
   - `/drop-gem` route now builds `PlacementScreen(initialLat/Lng from state.extra)`
   - Also: `lib/screens/gems/drop_gem_sheet.dart`, `lib/core/constants/gem_categories.dart`, `lib/core/services/`

4. **Router-race fix** (good, coherent, but fused with #2/#3 in shared files)
   - `app_router.dart`: `static final router` → `static GoRouter create(Listenable authRefresh)` + `refreshListenable`
   - `main.dart`: `ExplorIfeApp` StatelessWidget→StatefulWidget, holds `_auth`, `routerConfig: _router`

5. **Auth-race fix (Bug 1) — ALREADY APPLIED in working tree, uncommitted**
   - `main.dart` `ChangeNotifierProxyProvider2<AuthProvider, GemProvider, TripProvider>` `update`
     already has the guard: `if (previous != null && previous.userId == uid) return previous; return TripProvider(userId: uid ...)`
   - Depends on `TripProvider.userId` getter (trip_provider.dart:45, committed in c5db0a8). NOTHING to write for Bug 1.

## Bug 2 — still unfixed, but it's untracked-file territory
- `lib/screens/trip_setup/trip_setup_sheet.dart` `_onComplete` (lines 31-47): `context.pop()` then
  `context.push('/trips/${trip.id}/builder')` on the disposed context → nav silently no-ops in go_router.
  `mounted` checks present at L37/L41. `ScaffoldMessenger.of(context)` at L43 has no pre-async capture.
- Fix (per spec, NOT yet applied): capture `Navigator.of(context)` / `GoRouter.of(context)` /
  `ScaffoldMessenger.of(context)` BEFORE the await; `navigator.pop()` (Navigator, not go_router — sheet is a
  ModalBottomSheetRoute above the router); `router.push(...)`; `messenger.showSnackBar(...)` in catch.
  Add `// TODO(snackbar):` noting the sheet context may not reach a valid ScaffoldMessenger even with
  pre-async capture — separate follow-up = add `scaffoldMessengerKey` to root `MaterialApp`.
- Since the file is untracked, "the Bug 2 fix" = apply the correct pattern BEFORE the file's first commit.

## Compile facts (why nothing is partially shippable)
- `main.dart` won't build vs HEAD: needs untracked `trip_provider`, `splits_provider`.
- `app_router.dart` won't build vs HEAD: needs untracked `placement_screen`, `trip_routes`; references deleted `add_gem_screen` as gone.
- app_router.dart's diff = router-race fix + trip-routes wiring + gem-placement swap, all in the same hunks.

## Triage session checklist
1. Read every modified (~30) + untracked (~40+) file.
2. Group by workstream (the five above + auth-model migration deleting user.dart/user_provider.dart + explore/home rewrites).
3. Decide ship-vs-branch per group.
4. Commit each group as its own coherent unit.
5. Verify composite builds (`flutter build web --release`).
6. Deploy from a clean tree via `./deploy.sh` (NEVER git push — Vercel Git auto-deploy is intentionally disconnected).

Half-day session minimum. Not an hour.

---

## Canary process refinements — added 2026-07-07 (fresh, greppable)

Three standing rules for every canary submission going forward. Grep tag: CANARY-PROCESS.

1. **Cumulative refinement recap.** Open each canary with a two-line "Carrying
   forward from prior reviews" list of the 3–5 most recent refinements that still
   affect files NOT yet written. Refinements touching only closed files are not
   repeated.
2. **Caller-audit on contract changes.** When a refinement changes a method's
   exception contract, return type, or side-effect surface, grep + review the
   immediate callers (one level, non-recursive) before declaring the canary done.
   This is what would have caught the seedChecklistForTrip → createTrip lineage
   last round.
3. **Explicit status marker per canary.** Tag each canary section
   `Status: draft` | `Status: locked` | `Status: locked-with-active-refinements`.
   The middle state flags an already-approved method whose refinements affect
   not-yet-written files; it clears when those files land.

### Durable rule (added 2026-07-07, after an R1 miss)
Prior caveats affecting a proposed refinement MUST be surfaced in the recap
section of that refinement — this applies to lead-side refinements as well as
canary submissions. (Context: a proposed "fresh-list" refinement on
`checklistFor` was retracted — it described an in-place-list rebuild bug that
didn't exist, `checklistFor` already returns a fresh sorted list, and the
proposed replacement would have dropped the sort. An item-4 caveat from the
prior turn already covered the real behaviour; leading with the recap would have
caught the contradiction before it was written. No active "fresh-list"
refinement is carried forward.)

### Canary status board (seed)
- Migration `20260707000000_create_trip_checklist_items.sql` — Status: locked (on disk 2026-07-07).
- Models `trip_checklist_item.dart` / `trip_checklist_template.dart` — Status: locked.
- `TripProvider` checklist methods (checklistFor / toggleChecklistItem / seedChecklistForTrip / helpers) — Status: locked (analyze clean 2026-07-07).
- `TripSummaryScreen` + cards — Status: draft (shell canary in review).
- `expense_donut.dart` paint() — Status: draft (canary piece; written for review 2026-07-07).

## Summary donut vs Sidebar category breakdown — divergence note (2026-07-07)

Corrects an earlier framing that compared these as two donuts with different
arc-label formats. Verified against code (grep, 2026-07-07): **the sidebar has no
donut.** They render the SAME four budget buckets (stay/food/activity/transit)
with the SAME colour mapping (stay→primary, food→teal, activity→purple,
transit→pink), but are deliberately different CHART TYPES:

- **Summary donut** (`expense_donut.dart`): a stroked ring. Arc labels are
  PERCENTAGE-ONLY ("42%"); category identity is carried by a `ChartLegend`
  rendered INSIDE the `ExpenseDonut` widget's own `Column` (always present — a
  composing card cannot strip it without editing the widget). This is what makes
  Decision A (%-only arc labels, 2026-07-07) safe: the legend can never go
  missing, so the slice→category mapping is always available.
- **Sidebar breakdown** (`summary_sidebar.dart` `_CategoryBreakdown`): horizontal
  normalised bars, one per bucket, each with an INLINE text label ("Stays",
  "Food", "Activities", "Transit"). No arc, no percentages, no legend. (The only
  `%` in that file is the Budget bar's `status.pct`, unrelated.)

So there is NO arc-label-format divergence to reconcile — the sidebar has no arc
labels. The divergence is chart-TYPE (ring+internal-legend vs inline-labelled
bars), justified by geometry: the 320px sidebar has no room for a separate legend
surface, so it labels bars inline; the Summary card has vertical space for a ring
plus its own legend.

Revisit if: the sidebar gains a legend surface (e.g. a wider desktop sidebar
variant), OR the Summary donut is refactored so its legend becomes external and
optional (e.g. a mobile-compact Summary variant that drops it). Either change
removes the constraint that justifies the divergence — at that point re-evaluate
whether both should share the ring+legend pattern (and, for the compact case,
whether %-only arc labels must revert to "Category %").

SEPARATE inconsistency found in the same audit (NOT resolved here): category
label WORDING differs — donut says Stay/Do/Move, sidebar says
Stays/Activities/Transit. Same buckets, different display strings. It's a copy
decision AND retroactive to committed code, so it's a standalone follow-up, not
folded into the chart canary.

### Summary card canary — REQUIRED assertion (when TripSummaryScreen / donut card lands)
Decision A (%-only arc labels) is safe ONLY while a legend accompanies the donut.
Today it holds by construction: the `ChartLegend` is INTERNAL to `ExpenseDonut`
(its own Column), so it can't go missing. If a future refactor makes the legend
external/optional, the composing card MUST render one. Codify at the composition
site with a greppable marker:
    // composed with legend — Decision A (%-only arc labels) depends on this
If the card ever composes the donut WITHOUT a legend, revert arc labels to
"Category %" (the sidebar's inline-label pattern). Grep tag: `composed with legend`.

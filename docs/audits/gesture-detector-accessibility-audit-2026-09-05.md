# GestureDetector Accessibility & Tap-Target Audit — 2026-09-05

## Trigger

Code review of `lib/widgets/gems/linked_business_card.dart` (the shared
Gem Detail linked-business card, from the Restaurant business-profile PR)
found its "View full listing" control was a bare `GestureDetector`: no
`Semantics(button: true, label: ...)` (so a screen reader announces it as
plain static text, not an interactive control), no press feedback (no
`Material`+`InkWell`), and a touch target no larger than its text/icon
content. This is the same category of issue previously flagged on
`gem_detail_screen.dart`'s `_HeaderIcon` — the question was whether that
earlier fix was applied narrowly or broadly, and whether it should have
recurred in code written after it.

**Fixed** in `lib/widgets/gems/linked_business_card.dart` — wrapped in
`Semantics(button: true, label: 'View full listing')` +
`Material(color: transparent, child: InkWell(...))` with
`EdgeInsets.symmetric(vertical: 10, horizontal: 4)` padding around the
row, matching `_QuickActionButton`'s reference pattern in
`gem_detail_screen.dart`.

## Was the earlier `_HeaderIcon` fix applied narrowly or broadly?

**Narrowly — and even there, only half-fixed.** `_HeaderIcon`
(`gem_detail_screen.dart`) has `Semantics(button: true, label: ...)` but
is STILL a bare `GestureDetector` underneath — no `Material`/`InkWell`,
so it has an accessible label but no press feedback, and its 36×36 box
sits under the ~44px tap-target guideline. The earlier review only ever
caught the missing-Semantics half of this issue on that one widget; the
missing-press-feedback half was never addressed there either, and nothing
about that fix generalized to any other file. This audit is the first
time the full three-part checklist (Semantics + press feedback + tap
target) has been applied codebase-wide.

There are two genuinely different "correct" reference shapes in this
codebase, not one:
- **`_QuickActionButton`** (`gem_detail_screen.dart`): explicit
  `Semantics(button:true, label:...)` wrapping `Material`+`InkWell` — the
  fullest correct pattern, used as the template for the
  `LinkedBusinessCard` fix above.
- **`_AccordionSection`** (`gem_detail_screen.dart`): `Material`+`InkWell`
  for press feedback, but NO explicit `Semantics` wrapper — relies on
  `InkWell`'s own baseline tap-detection semantics rather than an
  explicit label. Not flagged as broken, but not the pattern to copy
  either if the tapped content doesn't already read sensibly on its own
  (e.g. plain title text does; an icon-only control does not).

## Full codebase audit

Searched `grep -rln "GestureDetector" lib/` — 42 files (41 outside
`linked_business_card.dart`, fixed above). Every usage was classified:

- **Bucket 1 — decorative/not interactive** (not flagged): 1 instance —
  `explore_screen.dart:590`, a tap-outside-to-dismiss search scrim.
- **Bucket 2 — already fine**: the `_BackIcon` widget, duplicated
  identically in `attraction_detail_screen.dart:292`,
  `restaurant_detail_screen.dart:343`, and `tour_detail_screen.dart:291`
  — has `Semantics(button:true, label:'Back')`. Caveat: still no
  `Material`/`InkWell` and sits at 36×36 (under the 44px guideline), so
  it's "fine" only in the narrow sense of having a screen-reader label;
  a stricter pass would flag it too.
- **Bucket 3 — needs fix**: **~140 instances across the remaining 40
  files.** The dominant gap by far is missing press feedback (true even
  where `Semantics` already exists — e.g. every one of `home_screen.dart`'s
  ~10 `GestureDetector`s, and `photo_info_card.dart`'s shared card shell,
  all have `Semantics(button:true,...)` but no `Material`/`InkWell`). The
  second most common gap is missing `Semantics` entirely — true for the
  majority of instances outside `home_screen.dart` and a handful of
  already-labeled card rows in `listings_screen.dart`/`tours_list_screen.dart`.
  Undersized tap targets are a narrower, distinct problem concentrated in
  bare-icon "×"/chevron/pencil controls with no padding — worst offenders:
  `photo_carousel.dart:151`'s page-indicator dots (6–18px wide, no
  padding — the smallest target found in the whole audit), and
  `trips_tab.dart`'s icon-only expand/edit/map-open controls at lines
  80/85/92 (16–22px icons, zero padding).

  **`lib/screens/profile/tabs/trips_tab.dart` is the single largest
  offender**: 23 separate `GestureDetector` usages, every one missing
  both `Semantics` and press feedback — this file alone is roughly a
  sixth of the total findings.

Full per-file, per-line findings (file:line, what it is, exactly which of
Semantics/press-feedback/tap-target is missing) are preserved in the
audit agent's output attached to this PR's description / this session's
transcript — not duplicated verbatim into this doc to keep it from
becoming a second copy of the raw findings; re-run the same audit prompt
against `git diff` if the raw per-line list is needed again later (the
line numbers here will drift as the codebase changes).

## Decision: fix `LinkedBusinessCard` now, file the rest as a backlog item

~140 instances across 40 files is far beyond what belongs in the PR that
found it — bundling a codebase-wide accessibility pass into the Restaurant
business-profile branch would make that PR unreviewable and mixes two
unrelated concerns (a new feature vs. a cross-cutting UI-consistency fix).
Per this task's own instruction to file large lists as explicit
follow-ups rather than force them into one PR: **not attempting the full
~140-instance fix in this change.**

Suggested reusable pattern for whoever picks this up (matches
`_QuickActionButton` exactly):
```dart
Semantics(
  button: true,
  label: '<what this control does>',
  child: Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: ...,
      borderRadius: BorderRadius.circular(<match the container's own radius>),
      child: Padding(
        padding: <enough to bring the effective tap target to ~44x44>,
        child: <existing content>,
      ),
    ),
  ),
),
```
A few call sites need a variant, not the plain button semantics above:
- `trips_tab.dart:1022`'s packing checkbox → `Semantics(checked: ...)`,
  not just `button: true`.
- Multi-select/toggle chips (`submit_story_screen.dart:199`,
  `step_two_template.dart:128`, `add_expense_sheet.dart:324`, several
  chip widgets in `trips_tab.dart`) → `Semantics(selected: ...)`.
- `side_drawer.dart:441`'s `_AccountTile` for the disabled PRO/SOON
  tiles → should also expose `Semantics(enabled: false)`, not just add
  a label.

**Recommended sequencing for the follow-up** (not started this round):
1. `photo_carousel.dart`'s page dots and `trips_tab.dart`'s 3 icon-only
   controls (lines 80/85/92) — the genuinely-too-small tap targets, the
   highest-severity subset.
2. `trips_tab.dart`'s remaining 20 instances as one batch (single file,
   single screen, highest instance count).
3. Everything else, file-by-file or screen-by-screen, lowest risk last
   since most of these are cosmetic-only (missing ripple) rather than a
   hard usability blocker.

Add "codebase-wide GestureDetector → Semantics+InkWell accessibility
pass (~140 instances, see this doc)" to the backlog.

## Triage & closeout — 2026-09-05 (round 2)

Before rolling out the broader ~140-instance backlog, three specific
items from round 1 were re-checked, since they affected whether this
doc's own numbers could be trusted.

### 1. `_HeaderIcon` was undercounted — now fixed

Confirmed: `_HeaderIcon` was excluded from the round-1 audit sweep on
the (correct, but incomplete) assumption that it was "already handled" —
it had been read and documented in prose (see "Was the earlier
`_HeaderIcon` fix applied narrowly or broadly?" above) but was never
formally tallied into Bucket 2 or Bucket 3, so the "~140 across 40
files" count silently excluded it. **The true round-1 count was ~141.**

**Fixed now**: `_HeaderIcon` wrapped in `Material`+`InkWell`
(`customBorder: CircleBorder()` to match its circular shape), on top of
its existing `Semantics`. Its 36×36 size was left as-is (not resized) —
same scope-discipline reasoning as everywhere else in this pass: this
was flagged as a two-line press-feedback fix, not a tap-target resize.

**The same exclusion-by-assumption risk applies to one more widget,
NOT fixed in this pass — flagging rather than silently fixing or
silently ignoring:** `_BackIcon` (duplicated in
`attraction_detail_screen.dart`, `restaurant_detail_screen.dart`,
`tour_detail_screen.dart`) was scored "Bucket 2 — already fine" in
round 1 specifically because it already had `Semantics`, using the same
reasoning that undercounted `_HeaderIcon` — it has the IDENTICAL gap
(`Semantics` yes, `Material`/`InkWell` no, 36×36 under the 44px
guideline). For consistency, this should probably be reclassified to
Bucket 3 (3 more instances, one shared component) rather than staying
"fine" — left for the backlog rather than fixed here since it wasn't
in this round's explicit scope, but the count should be treated as
**~141 + 3 `_BackIcon` instances currently mis-scored as fine**, not a
clean ~140. No other Bucket-2 entries share this exclusion reasoning
(`explore_screen.dart:590`'s scrim is genuinely decorative, not an
assumption-based exclusion).

### 2. `trips_tab.dart`'s 23 instances — triaged, not a flat 23-fix count

Manual pass (not just the raw grep count) confirmed: **all 23 have a
real, non-null `onTap` performing a genuine action — none are
decorative.** Breakdown:
- **13 standalone fixes** — each got its own `Semantics` (using
  `checked:`/`selected:`/`expanded:`/`enabled:` where the control isn't
  a plain button — the packing checkbox, `_SegmentedControl`,
  `_TypeChip`, `_DayRailChip`, the expense-row expand toggle, and the
  disabled-while-loading "Log expense" link all needed a variant, not
  bare `button: true`) + `Material`/`InkWell` press feedback. A new
  small shared `_TapIcon` widget was extracted for the 3 inline
  icon-only header controls (switch/edit/open-map) rather than fixing
  each independently, since they're the same shape with different
  icons/labels.
- **10 consolidated into 2 new shared widgets** rather than fixed 23
  independently:
  - **`_AddPill`** (5 call sites: Add Traveler/Document/Item/
    Booking/Expense) — confirmed verbatim-identical Dart, one widget
    now backs all 5, including the one loading-spinner variant
    ("+ Add Expense").
  - **`_PickerField`** (5 call sites: expiry date, activity time,
    booking start/end, itinerary-stop) — 4 were verbatim-identical; the
    itinerary-stop picker needed 2 extra optional parameters
    (`trailingChevron`, `iconColor`) for its richer layout, added to
    the same shared widget rather than left as a one-off.
- **0 correctly-excluded/decorative.**

So the real work behind "23 instances" was **13 standalone fixes + 2
shared-widget extractions covering the other 10** — confirmed exactly
as predicted by the triage pass, and **all of it is now fixed**, not
deferred. `flutter analyze`/`flutter test` clean after (see Verification
below) — the file now has zero `GestureDetector` usages left (`grep -c
GestureDetector trips_tab.dart` → 2, both matches are this doc's own
comment text, not code).

### 3. `photo_carousel.dart`'s page dots — genuinely interactive, fixed

Read the widget directly: `onTap: () => _jumpTo(i)` really does
`_controller.animateToPage(i, ...)` — **the dots are a real,
already-wired jump-to-photo interaction, not a purely visual pagination
indicator.** The "worst tap-target offender" framing from round 1 was
correct; nothing to walk back there.

Also confirmed there's no separate/stale implementation to worry about:
`GemDetailScreen` had its own private `_jumpToPhoto`/`_photoController`
at one point, but that was removed earlier this session when the screen
was refactored onto this shared `PhotoCarousel` widget — `photo_carousel.dart`
is now the *only* implementation, reused by Gem/Tour/Attraction/Restaurant
detail screens alike.

**Fixed**: each dot now gets `Semantics(button: true, label: 'Photo N
of count', selected: ...)`, `GestureDetector` behavior set to
`HitTestBehavior.opaque`, and extra `Padding` (not a larger visible
dot) around the existing 6px dot to enlarge the real hit area — full
~44×44 wasn't achievable without dots overlapping when a carousel has
several photos, so this is a meaningful, deliberate improvement (dot
height's tap area goes from 6px to ~36px) rather than hitting the exact
guideline number. No `Material`/`InkWell` ripple was added here
deliberately — a Material ripple on a 6px dot reads visually oddly for
such a small decorative element; the existing filled/unfilled color
swap already provides selected-state feedback. Flagging this as a
judgment call rather than deciding it silently.

## Verification (round 2)

`flutter analyze`: 44 issues, all info-level, identical set to the
pre-round-2 baseline (41 original + 3 pre-existing
`use_build_context_synchronously` infos in `RestaurantFormScreen`) — no
new issues from any round-2 change. `flutter test`: 361/361 pass, no
regressions.

**Not done this round**: a live browser/manual smoke test of the `My
Trip` tab and any photo carousel. The changes are structurally
conservative (wrapping existing widgets in `Semantics`/`Material`/
`InkWell`/`Padding` without changing `onTap` targets or decorations),
and were reviewed line-by-line against the original code before/after
each edit, but a few (the packing-item checkbox, the "+ ADD" slot
link) do add real padding that shifts adjacent spacing by a few
pixels — worth a visual spot-check of the My Trip tab's Itinerary/
Bookings/Packing sections before this ships, since that wasn't
independently verified here.

## `_BackIcon` tracked, and a full re-check for the same exclusion bug — 2026-09-05 (round 3)

Round 2 flagged `_BackIcon` in prose but never gave it individually
tracked entries the way every other Bucket-3 finding has — exactly the
kind of vague "and similar cases" mention that let `_HeaderIcon` almost
slip through uncounted in the first place. Fixing that here.

### `_BackIcon` — 3 tracked instances, reclassified Bucket 2 → Bucket 3

| File | Line | Gap |
|---|---|---|
| `lib/screens/attractions/attraction_detail_screen.dart` | 292 | `Semantics(button:true, label:'Back')` present; no `Material`/`InkWell`; 36×36 box, under the ~44px guideline |
| `lib/screens/restaurants/restaurant_detail_screen.dart` | 343 | Same gap, same widget |
| `lib/screens/tours/tour_detail_screen.dart` | 291 | Same gap, same widget — confirmed the file's own `Material`/`InkWell` usages (lines 240, 466, 533/535) belong to *other*, already-correct widgets in that file, not `_BackIcon` itself |

All 3 are the same private `_BackIcon` widget, copy-pasted across the
three detail screens rather than shared — fixing it once as a shared
widget (mirroring how `LinkedBusinessCard`/`_TapIcon`/`_AddPill`/
`_PickerField` were already extracted this round) covers all 3 and
would be the natural fix when this is picked up, rather than patching
each file independently. **Not fixed in this pass** — tracked here so
it can't be missed again, but implementing it wasn't in this round's
scope.

### Root cause, for the audit's own methodology

The actual failure mode: **a component gets wrongly excluded from a
sweep because an earlier partial fix (Semantics added, press feedback
never added) makes a shallow check see "has `Semantics`" and stop
there, treating that as "already handled."** This is exactly what
happened to `_HeaderIcon` (excluded from round 1's sweep entirely,
on my own instruction to the auditing pass, because I'd already
confirmed it had *some* fix applied) and to `_BackIcon` (scored
"Bucket 2 — already fine" using the same shallow "has `Semantics`,
must be done" logic).

**Recommendation for any future pass over this codebase (or a similar
one): before marking anything "already fixed" or excluding it from a
sweep, check for BOTH `Semantics` AND a press-feedback wrapper
(`Material`+`InkWell`, or an equivalent explicit visual-feedback
mechanism) — never treat the presence of `Semantics` alone as
sufficient evidence a control is done.** A single `grep -c` for
`Semantics(` in a file is not a substitute for confirming a
`Material`/`InkWell` sits between it and the `GestureDetector`.

### One-more-pass check: did this exclude anything beyond `_HeaderIcon`/`_BackIcon`?

Re-ran the search specifically for "has `Semantics` but the file has
zero `Material`/`InkWell`" — i.e. every file with both `Semantics(`
and `GestureDetector` was re-counted for `Semantics(`/`GestureDetector`/
`InkWell`/`Material(` occurrences and manually re-verified against
round 1's per-line findings:

| File | `Semantics(` | `GestureDetector` | `InkWell`/`Material(` |
|---|---|---|---|
| `attraction_detail_screen.dart` | 1 | 1 | 0 — `_BackIcon`, now tracked above |
| `home_screen.dart` | 10 | 10 (11th grep hit is a comment, not code) | 0 |
| `listings_screen.dart` | 5 | 8 | 0 |
| `restaurant_detail_screen.dart` | 1 | 1 | 0 — `_BackIcon`, now tracked above |
| `tour_detail_screen.dart` | 1 | 1 | 2/2 — but confirmed those belong to *other* widgets in the file, not `_BackIcon` (still bare) |
| `tours_list_screen.dart` | 1 | 1 | 0 |
| `photo_info_card.dart` | 1 | 1 | 0 |

**Result: confirmed — no instance beyond `_HeaderIcon` and the 3
`_BackIcon` copies was affected.** `home_screen.dart`'s 10,
`listings_screen.dart`'s 5-with-`Semantics` (of its 8 total),
`tours_list_screen.dart`'s 1, and `photo_info_card.dart`'s 1 — 17
instances total — all already had explicit, individually-tracked
Bucket-3 entries in round 1 (see the earlier per-file findings); they
were never silently excluded, just correctly identified as "not yet
fixed" rather than "already fine." The exclusion bug was scoped to
exactly the 4 widgets I explicitly told the round-1 audit agent to
skip as "already handled" (`_HeaderIcon`, `_QuickActionButton`,
`_AccordionSection`, `_BackIcon`) — of those 4, only `_HeaderIcon`
(now fixed) and `_BackIcon` (now tracked, 3 instances) actually had
the gap; `_QuickActionButton` is genuinely complete and
`_AccordionSection` genuinely has press feedback (its own, separately-
noted gap is the *inverse* one — press feedback without an explicit
`Semantics` label — not this failure mode).

**Corrected total remaining backlog: ~137 instances across ~39 files**
(the original ~141 minus `_HeaderIcon`, `trips_tab.dart`'s 23, and
`photo_carousel.dart`'s dots, all fixed in round 2) **plus the 3
`_BackIcon` instances now tracked above** — i.e. ~137 + 3 = ~140,
none of them silently missing from the count anymore.

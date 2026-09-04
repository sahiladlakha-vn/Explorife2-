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

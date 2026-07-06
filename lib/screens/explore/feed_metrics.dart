// Pure, dependency-free metrics for the discovery feed: the sheet's named snap
// points and the distance-pill label. No Flutter widgets, Supabase or
// Geolocator here so the logic is trivially unit-testable and the same numbers
// drive the sheet, the host wiring and the tests.

/// Named snap points for the discovery sheet — the single source of truth for
/// how far the draggable sheet opens. Retuning a detent is a one-line change
/// here; every widget and the host wiring read these values.
///
/// The sheet is now a TWO-detent surface (the half "card row" detent was retired
/// when the floating card deck became the primary browse surface):
/// * [peek] — a thin collapsed handle + header (city + count + filter chips);
///   the floating deck and the map are the hero at rest.
/// * [full] — the complete vertical feed (a thin map strip stays on top).
enum SheetSnap {
  /// FALLBACK only. The live peek detent is MEASURED to hug the header region
  /// (see [peekFractionFor]); this constant is used solely before first layout
  /// or when the available height is unknown.
  peek(0.32),
  full(0.90);

  const SheetSnap(this.size);

  /// Fraction of the screen height this snap occupies.
  final double size;

  /// Landing detent on entering the Map tab is ALWAYS the content-hugging peek,
  /// regardless of gem count — the list is revealed by dragging up, never shown
  /// at rest. Kept as a named constant so callers don't sprinkle `SheetSnap.peek`.
  static const SheetSnap landing = peek;

  /// Upper bound for the measured peek fraction, so a tall header can never push
  /// peek up into list territory. Tunable midpoint between the two real detents.
  static const double _peekMaxFraction = 0.53;

  /// Peek detent as a fraction of [availableHeight], derived purely from the
  /// content-true [headerHeight] — so peek HUGS the strip with no blank band,
  /// instead of a magic fraction. The bottom safe-area inset is intentionally
  /// NOT added here: the sheet sits ABOVE the app's bottom nav bar (which is
  /// itself SafeArea-wrapped and already owns that inset), so folding it in
  /// double-counts and reintroduces dead space below the line.
  ///
  /// The lower clamp bound is 0.0 — NO positive FRACTIONAL floor. A fraction
  /// can't know the content's pixel height, so any fractional floor that
  /// exceeds the content fraction (56/availableHeight ≈ 0.07 on a normal
  /// viewport vs an 0.12 floor) re-inflates peek above the strip and re-creates
  /// the white band below the line. Peek tracks the fixed/measured content
  /// height: `f` resolves to exactly [headerHeight] px when multiplied back by
  /// [availableHeight]. The fixed, non-zero [headerHeight] is the real floor —
  /// peek can never collapse to nothing — and the early return guards div-by-0.
  static double peekFractionFor({
    required double headerHeight,
    required double availableHeight,
  }) {
    assert(headerHeight > 0, 'peek must hug a real, non-zero content height');
    if (availableHeight <= 0) return peek.size;
    final f = headerHeight / availableHeight;
    return f.clamp(0.0, _peekMaxFraction);
  }

  /// Full detent as a fraction of [availableHeight], CAPPED so the sheet's top
  /// edge stops at [topReservedPx] from the top — i.e. a fixed gap below the
  /// floating filter-chip row, which is an independent layer above the map. The
  /// chips never get clipped by the rising sheet. Capped above by the tunable
  /// [full] constant (so it can only get shorter, never taller). There is NO
  /// lower floor on the cap: on a very short viewport a shorter sheet is the
  /// correct trade-off over one that rises into the chips. (The sheet enforces
  /// `full >= peek` itself, so the DraggableScrollableSheet bounds stay valid.)
  static double fullFractionFor({
    required double topReservedPx,
    required double availableHeight,
  }) {
    if (availableHeight <= 0) return full.size;
    final f = (availableHeight - topReservedPx) / availableHeight;
    return f.clamp(0.0, full.size);
  }

  /// Snap extents in ascending order for a MEASURED [peek] fraction and the
  /// CAPPED [full] fraction. Single source for `snapSizes`.
  static List<double> snapSizesFor(double peek, double full) => [peek, full];

  /// The named snap closest to a raw [extent], given the measured [peek] and
  /// capped [full] fractions — lets the sheet derive its logical state from the
  /// one controller extent without duplicating threshold math.
  static SheetSnap nearestFor(double extent, double peek, double full) {
    final toPeek = (extent - peek).abs();
    final toFull = (extent - full).abs();
    return toPeek <= toFull ? SheetSnap.peek : SheetSnap.full;
  }

  /// True only at [full] — the vertical list state.
  bool get isFull => this == SheetSnap.full;

  /// True only at [peek] — the collapsed handle state (deck + map are the hero).
  bool get isPeek => this == SheetSnap.peek;
}

/// Height (logical px) of the sheet's THIN peek strip — grab handle + the single
/// "<City> · <n> spots · drag up for list" line, nothing else. The filter chips
/// moved out to a floating row under the search bar, and the big Bebas city
/// title moved into the expanded full-list view, so the collapsed sheet is now
/// just this one strip. The single source for BOTH the pinned header's extent
/// AND the measured peek detent, so peek always hugs exactly the strip drawn.
/// Sized to the strip's real content (top pad 12 + handle 4 + gap 12 + one
/// 13.5px line ≈ 17 + bottom pad 11), so there's no top-packed dead band.
const double kSheetPeekHeight = 56;

/// Gap (logical px) the floating card deck floats above the sheet's top edge at
/// the peek detent. Drives the deck anchoring so it sits just clear of the
/// collapsed handle rather than overlapping it.
const double kDeckGapAboveSheet = 12;

/// Fixed clear-air (logical px) kept between the floating filter-chip row and
/// the sheet's top edge at FULL. The chips are an independent layer above the
/// map; this caps the sheet's expanded height so its rounded top always stops
/// this far below the chips and can never clip them.
const double kSheetTopGapBelowChips = 12;

// ── Floating top-bar geometry (search field + filter chips) ──
// All FIXED logical-px heights, so the chip row's bottom edge is DERIVED ONCE
// (see [chipBandTop]) and shared by BOTH the map gesture shield and the sheet's
// full-detent cap — no geometry literal is duplicated across call sites. The
// widgets that draw the bar read these same tokens, so the derived offset can
// never drift from what's rendered.
const double kSearchBarTopPad = 12; // SafeArea content top padding
const double kSearchBarHeight = 52; // the rounded search pill
const double kChipsTopGap = 10; // gap between the search bar and the chip row
const double kFilterChipBarHeight = 44; // the horizontal chip row

/// Y (logical px from the body's top) of the filter-chip row's TOP edge, given
/// the top safe-area [topInset]. The bar is a `SafeArea > Padding > Column`
/// (search field then chips), so its offset is the sum of the fixed heights
/// above the chips. Single source for the shield band and the sheet cap.
double chipBandTop(double topInset) =>
    topInset + kSearchBarTopPad + kSearchBarHeight + kChipsTopGap;

/// Gap (logical px) the FAB + map controls float above the sheet's top edge, at
/// every detent. Drives the FAB anchoring so it's never buried by the sheet.
const double kFabGapAboveSheet = 20;

/// Gap (logical px) the "Drop a gem" pill + right control cluster float above
/// the floating deck card's top edge, so each owns its own vertical band and
/// the controls never overlap the card (the prior collision bug).
const double kDropGapAboveDeck = 14;

/// Cross-fade duration when the full-screen map-loading overlay tears down and
/// the live map fades in — the moment the gem fetch future completes.
const Duration kMapLoadFade = Duration(milliseconds: 450);

/// One pulse of the loading beacon: the location dot's ring expands + fades over
/// this period, then repeats. Tunable here so the cadence stays in config.
const Duration kBeaconPulse = Duration(milliseconds: 1600);

/// One sweep of the skeleton shimmer across the loading card's placeholder
/// blocks. Drives the GemCard-shaped skeleton while gems load.
const Duration kSkeletonShimmer = Duration(milliseconds: 1100);

/// Human-readable distance label from a straight-line distance in [meters], or
/// `null` when the distance is unknown (missing user location or gem coords) so
/// the caller can hide the pill entirely rather than render a placeholder.
///
/// Under ~950 m it reads in metres ("120 m"); above that in kilometres, with
/// one decimal up to 10 km and whole kilometres beyond.
String? gemDistanceLabel(double? meters) {
  if (meters == null || meters.isNaN || meters.isInfinite || meters < 0) {
    return null;
  }
  if (meters < 950) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
}

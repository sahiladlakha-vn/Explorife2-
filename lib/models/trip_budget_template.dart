import 'trip_vibe.dart';

/// Vibe-based default budget split for the Summary Planned-vs-Actual chart.
///
/// Seeded at trip creation (`TripProvider.seedCategoryBudgetsForTrip`) so the
/// chart has a "planned" baseline before the user edits anything. The editing
/// UI is deferred, so these proportions are the only planned source today.
///
/// Mirrors the [ChecklistSeed] convention: plain Dart, one source of truth for
/// "how does each vibe want its money split", read by the provider seed.

/// The four spend buckets the chart renders. Kept in sync with
/// [TripProvider.categoryTotals] (four buckets), NOT the migration's eight-value
/// CHECK constraint — those extra buckets are reserved, not yet seeded.
const List<String> budgetCategories = ['stay', 'food', 'activity', 'transit'];

/// Fraction of the total budget each bucket gets, per vibe. Each map sums to
/// 1.0 across [budgetCategories]. The lean per vibe:
///   slow    — stays + long meals dominate (depth over breadth)
///   fast    — activities + transit dominate (hikes, road trips)
///   foodie  — food dominates
///   romance — stays dominate (quiet luxury)
///
/// SOURCE: rough proportions hand-derived from Explorife's target audience's
/// typical trip patterns (Vietnam-based Gen Z travelers, mixed-mode trips), NOT
/// from measured user data. Treat as reasonable seed defaults, not ground truth.
/// If these ever get retuned against real spend data, note the data source here
/// so a future maintainer knows whether to trust them or rederive.
const Map<TripVibe, Map<String, double>> _proportionsByVibe = {
  TripVibe.slow: {'stay': 0.40, 'food': 0.30, 'activity': 0.20, 'transit': 0.10},
  TripVibe.fast: {'stay': 0.25, 'food': 0.20, 'activity': 0.35, 'transit': 0.20},
  TripVibe.foodie: {'stay': 0.30, 'food': 0.40, 'activity': 0.20, 'transit': 0.10},
  TripVibe.romance: {'stay': 0.45, 'food': 0.30, 'activity': 0.15, 'transit': 0.10},
};

/// Even-ish split for a trip with no vibe set (legacy trips, or a draft that
/// skipped Step 1). Slightly weights stay/food since lodging + eating are the
/// unavoidable floor of any trip.
const Map<String, double> _defaultProportions = {
  'stay': 0.35,
  'food': 0.30,
  'activity': 0.20,
  'transit': 0.15,
};

Map<String, double> _proportionsFor(TripVibe? vibe) =>
    _proportionsByVibe[vibe] ?? _defaultProportions;

/// Resolves [vibe] + [budgetVnd] into a planned VND amount per bucket.
///
/// Integer VND (single-currency app), so each bucket is rounded. Rounding drift
/// is absorbed into 'stay' (the largest bucket) so the parts sum EXACTLY to
/// [budgetVnd] — the chart's planned total then matches the trip budget with no
/// off-by-a-few-dong gap. A zero/negative budget yields all-zero planned values.
Map<String, int> plannedBudgetFor(TripVibe? vibe, int budgetVnd) {
  if (budgetVnd <= 0) {
    return {for (final c in budgetCategories) c: 0};
  }
  final props = _proportionsFor(vibe);
  final result = <String, int>{
    for (final c in budgetCategories)
      c: (budgetVnd * (props[c] ?? 0)).round(),
  };
  final assigned = result.values.fold(0, (a, b) => a + b);
  result['stay'] = result['stay']! + (budgetVnd - assigned);
  return result;
}

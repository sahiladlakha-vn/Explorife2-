// Pure derived-insight logic for a trip: alerts, budget pace, and badges.
//
// This file is deliberately UI-free and provider-free — it imports only the two
// plain models it reasons over. Every function takes its inputs as plain values
// (including the current time as a `DateTime now` parameter, never DateTime.now()
// internally) so the whole file is deterministic and unit-testable.
//
// MONEY RULE (restated per function below): amounts follow the house VND
// contract. For bookings, amountVnd == null means the price is UNKNOWN (TBD) and
// is EXCLUDED from every actual/spend sum; 0 means a genuinely free item and
// COUNTS. Never coalesce null to 0.

import '../../models/trip_stop.dart';
import '../../models/trip_booking.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Alerts
// ─────────────────────────────────────────────────────────────────────────────

/// What an [Alert] is about. The UI switches on this to pick copy + an icon.
enum AlertKind { unbookedStop, overBudgetCategory, upcomingBooking }

/// How loud an [Alert] should be. Ordered least → most urgent so `.index`
/// gives a natural severity ranking.
enum AlertSeverity { info, warning, critical }

/// A single derived, data-only notice about a trip. Carries structured fields
/// (ids, category, a small int payload) rather than a formatted string, so the
/// UI owns all copy and localization. [payload] values are VND amounts or day
/// counts depending on [kind]; keys are documented at each producer.
class Alert {
  final AlertKind kind;
  final AlertSeverity severity;
  final String tripId;

  /// Set for [AlertKind.unbookedStop]; null otherwise.
  final String? stopId;

  /// Set for [AlertKind.upcomingBooking]; null otherwise.
  final String? bookingId;

  /// Set for [AlertKind.overBudgetCategory] (e.g. 'food'); null otherwise.
  final String? category;

  /// Small structured extras, e.g. {'priceVnd': …}, {'overVnd': …},
  /// {'daysUntil': …}. Always ints; never a pre-formatted string.
  final Map<String, int> payload;

  const Alert({
    required this.kind,
    required this.severity,
    required this.tripId,
    this.stopId,
    this.bookingId,
    this.category,
    this.payload = const {},
  });
}

/// Stops with nothing booked against them yet. A stop is "unbooked" when no
/// booking of ANY status is pinned to its id — once even a `to_book` row exists
/// the user has started tracking it, so it no longer nags here.
///
/// MONEY RULE: this producer doesn't sum money; it only surfaces the stop's own
/// [TripStop.priceVnd] as context in the payload.
List<Alert> unbookedStopAlerts({
  required String tripId,
  required List<TripStop> stops,
  required List<TripBooking> bookings,
}) {
  final pinned = <String>{
    for (final b in bookings)
      if (b.stopId != null) b.stopId!,
  };
  return [
    for (final s in stops)
      if (!pinned.contains(s.id))
        Alert(
          kind: AlertKind.unbookedStop,
          severity: AlertSeverity.info,
          tripId: tripId,
          stopId: s.id,
          payload: {'priceVnd': s.priceVnd},
        ),
  ];
}

/// Categories whose actual spend has passed its planned envelope. Caller passes
/// the two maps it already computes (TripProvider.plannedByCategory /
/// categoryTotals) so this stays pure. Only categories with a positive plan are
/// judged — a zero/absent plan has no envelope to exceed.
///
/// MONEY RULE: the input maps are pre-summed by the caller under the same
/// null-excluded/0-counted contract; this function only compares them.
List<Alert> overBudgetCategoryAlerts({
  required String tripId,
  required Map<String, int> plannedByCategory,
  required Map<String, int> actualByCategory,
}) {
  final out = <Alert>[];
  plannedByCategory.forEach((category, planned) {
    if (planned <= 0) return;
    final actual = actualByCategory[category] ?? 0;
    if (actual <= planned) return;
    final over = actual - planned;
    // ≥25% over is critical, anything above the line is a warning.
    final severity =
        over * 4 >= planned ? AlertSeverity.critical : AlertSeverity.warning;
    out.add(Alert(
      kind: AlertKind.overBudgetCategory,
      severity: severity,
      tripId: tripId,
      category: category,
      payload: {
        'plannedVnd': planned,
        'actualVnd': actual,
        'overVnd': over,
      },
    ));
  });
  return out;
}

/// Bookings starting within [horizon] of [now]. A still-`to_book` item that is
/// imminent is critical (you haven't actually reserved it yet); a `booked`/`paid`
/// one is an informational heads-up. Past and undated bookings are ignored.
List<Alert> upcomingBookingAlerts({
  required String tripId,
  required List<TripBooking> bookings,
  required DateTime now,
  Duration horizon = const Duration(days: 3),
}) {
  final cutoff = now.add(horizon);
  final out = <Alert>[];
  for (final b in bookings) {
    final start = b.startAt;
    if (start == null) continue;
    if (start.isBefore(now) || start.isAfter(cutoff)) continue;
    final daysUntil = start.difference(now).inDays;
    out.add(Alert(
      kind: AlertKind.upcomingBooking,
      severity: b.status == BookingStatus.toBook
          ? AlertSeverity.critical
          : AlertSeverity.info,
      tripId: tripId,
      bookingId: b.id,
      payload: {'daysUntil': daysUntil},
    ));
  }
  return out;
}

/// All three alert families for a trip, most-urgent first. The sort is by
/// [AlertSeverity] descending; ties keep producer order (unbooked → over-budget
/// → upcoming), which is stable because we sort a pre-ordered list with a stable
/// comparator fallback on original index.
List<Alert> tripAlerts({
  required String tripId,
  required List<TripStop> stops,
  required List<TripBooking> bookings,
  required Map<String, int> plannedByCategory,
  required Map<String, int> actualByCategory,
  required DateTime now,
}) {
  final all = <Alert>[
    ...unbookedStopAlerts(tripId: tripId, stops: stops, bookings: bookings),
    ...overBudgetCategoryAlerts(
      tripId: tripId,
      plannedByCategory: plannedByCategory,
      actualByCategory: actualByCategory,
    ),
    ...upcomingBookingAlerts(tripId: tripId, bookings: bookings, now: now),
  ];
  // Stable severity-desc: pair with original index, sort, unwrap.
  final indexed = [
    for (var i = 0; i < all.length; i++) (i, all[i]),
  ];
  indexed.sort((a, b) {
    final bySeverity = b.$2.severity.index.compareTo(a.$2.severity.index);
    return bySeverity != 0 ? bySeverity : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

// ─────────────────────────────────────────────────────────────────────────────
// Spend composition (shared by pace + category alerts)
// ─────────────────────────────────────────────────────────────────────────────

/// Stop ids whose own estimate is SUPERSEDED by a committed (booked or paid)
/// booking pinned to them. Both [computePace] and [actualSpendByCategory] drop
/// these stops' priceVnd so a pinned booking never double-counts with the stop
/// it replaces. A `to_book` booking does NOT supersede — nothing is committed
/// yet, so the stop's estimate still stands.
///
/// This is the ONLY dedup implementation; the pace lens and the category-actual
/// lens both call it, so they can never disagree about which stops are
/// superseded.
Set<String> supersededStopIds(List<TripBooking> bookings) => {
      for (final b in bookings)
        if (b.stopId != null &&
            (b.status == BookingStatus.booked ||
                b.status == BookingStatus.paid))
          b.stopId!,
    };

/// The budget bucket a booking rolls up to, derived from
/// [TripBooking.bookingType] alone (pure). Flights and ground transport both
/// fall under 'transit'; there is no 'food' booking type, so bookings never land
/// in the food envelope — only stops do, via the caller-supplied stop bucketer.
String bookingCategory(TripBooking b) => switch (b.bookingType) {
      BookingType.stay => 'stay',
      BookingType.activity => 'activity',
      BookingType.flight => 'transit',
      BookingType.transport => 'transit',
    };

/// Committed spend per budget bucket, deduped against pinned bookings.
///
/// LENS — WHOLE-TRIP COMMITTED, deliberately NOT time-phased: every
/// non-superseded stop estimate and every committed booking counts regardless of
/// date, because a category envelope is a total-trip allocation — a
/// booked-but-future hotel already consumes the stay envelope, and an alert that
/// stayed silent until check-in night would be useless. [computePace] applies
/// day-attribution (time-phasing) ON TOP of this same composition for its pace
/// lens. The two lenses share the money contract and [supersededStopIds] dedup
/// but differ on time-phasing BY DESIGN — do not "fix" the difference by
/// aligning them.
///
/// Rules (shared with [computePace] except the time gate):
///  • DEDUP: stops in [supersededStopIds] contribute nothing (the booking that
///    superseded them counts in the booking's own category instead).
///  • MONEY: a booking with amountVnd == null is TBD and excluded; 0 counts.
///  • COMMITTED: `paid` and `booked` bookings count; `to_book` never does.
///
/// [stopCategory] buckets a stop (provider-supplied, since it needs the gem
/// catalogue); bookings are bucketed by the pure [bookingCategory] above. Only
/// non-zero-yielding buckets appear as keys — the caller zero-fills for display.
Map<String, int> actualSpendByCategory({
  required List<TripStop> stops,
  required List<TripBooking> bookings,
  required String Function(TripStop) stopCategory,
}) {
  final superseded = supersededStopIds(bookings);
  final out = <String, int>{};
  for (final s in stops) {
    if (superseded.contains(s.id)) continue;
    final cat = stopCategory(s);
    out[cat] = (out[cat] ?? 0) + s.priceVnd;
  }
  for (final b in bookings) {
    if (!b.hasKnownAmount) continue; // null == TBD, excluded (0 stays in).
    if (b.status == BookingStatus.toBook) continue; // not committed.
    final cat = bookingCategory(b);
    out[cat] = (out[cat] ?? 0) + b.amountVnd!;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pace
// ─────────────────────────────────────────────────────────────────────────────

/// Where the trip's spend sits relative to a straight-line burn of the budget.
enum PaceStatus { notStarted, noBudget, underPace, onPace, overPace }

/// The result of [computePace]. All money fields are VND ints. [delta] is
/// `cumulativeActual - expectedByToday` (positive = spending ahead of pace).
/// [projectedExhaustionDay] is the 1-based trip day the budget is forecast to
/// run out, or null when it won't within the trip (or can't be projected).
class TripPace {
  final PaceStatus status;
  final int cumulativeActual;
  final int expectedByToday;
  final int delta;
  final int? projectedExhaustionDay;

  /// 1-based day index of `now` within the trip (day 1 == trip start). Clamped
  /// into [0, tripDays] for display; 0 means the trip hasn't started.
  final int tripDayToday;
  final int tripDays;

  const TripPace({
    required this.status,
    required this.cumulativeActual,
    required this.expectedByToday,
    required this.delta,
    required this.projectedExhaustionDay,
    required this.tripDayToday,
    required this.tripDays,
  });
}

/// Date-only day index of [when] relative to [start]; day 1 == the start date.
int _dayIndex(DateTime start, DateTime when) {
  final a = DateTime(start.year, start.month, start.day);
  final b = DateTime(when.year, when.month, when.day);
  return b.difference(a).inDays + 1;
}

/// Straight-line pace check for a trip's spend.
///
/// CUMULATIVE-ACTUAL COMPOSITION — three rules, all under the MONEY RULE
/// (a booking with amountVnd == null is TBD and never summed):
///
///  1. DEDUP PINNED BOOKINGS: when a COMMITTED booking (booked or paid) has a
///     non-null stopId, that stop's priceVnd is EXCLUDED from the sum — the
///     booking supersedes the stop's estimate so the two never double-count.
///     (This holds even when the booking itself isn't counted yet under rule 3,
///     e.g. a future `booked` leg: the stop estimate still drops out.)
///
///  2. STOP DAY ATTRIBUTION: a stop contributes its priceVnd only when its trip
///     day (TripStop.day, 1-based) is ≤ today's trip day. Future days don't
///     count toward money already spent.
///
///  3. BOOKING DAY ATTRIBUTION: `paid` always counts (real cash out, regardless
///     of start date); `booked` counts only if startAt != null && startAt ≤ now
///     (a null startAt is excluded); `to_book` NEVER counts, even with a known
///     amount.
TripPace computePace({
  required int totalBudgetVnd,
  required List<TripStop> stops,
  required List<TripBooking> bookings,
  required DateTime tripStart,
  required int tripDays,
  required DateTime now,
}) {
  final days = tripDays < 1 ? 1 : tripDays;
  final rawDayToday = _dayIndex(tripStart, now);
  final dayToday = rawDayToday.clamp(0, days);

  // Rule 1: stops superseded by a committed pinned booking — via the shared
  // [supersededStopIds] primitive so the pace and category-actual lenses can
  // never diverge on which stops drop out.
  final superseded = supersededStopIds(bookings);

  var cumulative = 0;

  // Rule 2: stop estimates up to and including today, minus superseded stops.
  for (final s in stops) {
    if (superseded.contains(s.id)) continue;
    if (s.day <= dayToday) cumulative += s.priceVnd;
  }

  // Rule 3: booking actuals, honoring status + date + the null-amount exclusion.
  for (final b in bookings) {
    if (!b.hasKnownAmount) continue; // null == TBD, excluded (0 stays in).
    final amount = b.amountVnd!;
    switch (b.status) {
      case BookingStatus.paid:
        cumulative += amount;
      case BookingStatus.booked:
        if (b.startAt != null && !b.startAt!.isAfter(now)) cumulative += amount;
      case BookingStatus.toBook:
        break; // never counts
    }
  }

  if (rawDayToday < 1) {
    return TripPace(
      status: PaceStatus.notStarted,
      cumulativeActual: cumulative,
      expectedByToday: 0,
      delta: cumulative,
      projectedExhaustionDay: null,
      tripDayToday: 0,
      tripDays: tripDays,
    );
  }

  if (totalBudgetVnd <= 0) {
    return TripPace(
      status: PaceStatus.noBudget,
      cumulativeActual: cumulative,
      expectedByToday: 0,
      delta: cumulative,
      projectedExhaustionDay: null,
      tripDayToday: dayToday,
      tripDays: tripDays,
    );
  }

  final expected = (totalBudgetVnd * dayToday / days).round();
  final delta = cumulative - expected;

  // 5% band around the expected line keeps `onPace` meaningful.
  final band = (expected * 0.05).round();
  final PaceStatus status;
  if (delta > band) {
    status = PaceStatus.overPace;
  } else if (delta < -band) {
    status = PaceStatus.underPace;
  } else {
    status = PaceStatus.onPace;
  }

  // Forecast exhaustion from the burn rate so far. Only meaningful if we're
  // actually burning and the forecast lands within the trip window.
  int? exhaustionDay;
  if (cumulative > 0) {
    final dailyRate = cumulative / dayToday;
    final day = (totalBudgetVnd / dailyRate).ceil();
    if (day >= 1 && day <= days) exhaustionDay = day;
  }

  return TripPace(
    status: status,
    cumulativeActual: cumulative,
    expectedByToday: expected,
    delta: delta,
    projectedExhaustionDay: exhaustionDay,
    tripDayToday: dayToday,
    tripDays: tripDays,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Badges
// ─────────────────────────────────────────────────────────────────────────────

/// The countable dimension a badge is earned against. [evaluateBadges] is fed a
/// map from this enum to the user's current count for each.
enum BadgeMetric { gems, trips, stories, bookings }

/// A static badge definition: identity + display copy + the metric/threshold
/// that earns it. Copy lives here (approved) so the UI has no hardcoded strings.
class BadgeDef {
  final String id;
  final String label;
  final String description;
  final BadgeMetric metric;
  final int threshold;

  const BadgeDef({
    required this.id,
    required this.label,
    required this.description,
    required this.metric,
    required this.threshold,
  });
}

/// The catalogue. Ordered by metric then ascending threshold so a UI can render
/// tiers in-order without re-sorting.
const List<BadgeDef> kBadges = [
  BadgeDef(
    id: 'first_gem',
    label: 'First Find',
    description: 'Save your first gem.',
    metric: BadgeMetric.gems,
    threshold: 1,
  ),
  BadgeDef(
    id: 'gem_collector',
    label: 'Collector',
    description: 'Save 10 gems.',
    metric: BadgeMetric.gems,
    threshold: 10,
  ),
  BadgeDef(
    id: 'gem_curator',
    label: 'Curator',
    description: 'Save 50 gems.',
    metric: BadgeMetric.gems,
    threshold: 50,
  ),
  BadgeDef(
    id: 'first_trip',
    label: 'Trailhead',
    description: 'Plan your first trip.',
    metric: BadgeMetric.trips,
    threshold: 1,
  ),
  BadgeDef(
    id: 'globetrotter',
    label: 'Globetrotter',
    description: 'Plan 5 trips.',
    metric: BadgeMetric.trips,
    threshold: 5,
  ),
  BadgeDef(
    id: 'first_story',
    label: 'Storyteller',
    description: 'Publish your first story.',
    metric: BadgeMetric.stories,
    threshold: 1,
  ),
  BadgeDef(
    id: 'chronicler',
    label: 'Chronicler',
    description: 'Publish 10 stories.',
    metric: BadgeMetric.stories,
    threshold: 10,
  ),
  BadgeDef(
    id: 'first_booking',
    label: 'Booked In',
    description: 'Log your first booking.',
    metric: BadgeMetric.bookings,
    threshold: 1,
  ),
  BadgeDef(
    id: 'planner',
    label: 'Planner',
    description: 'Log 10 bookings.',
    metric: BadgeMetric.bookings,
    threshold: 10,
  ),
];

/// A badge paired with the user's progress toward it. [progress] is clamped to
/// [0, 1]; [earned] is true once [current] reaches the def's threshold.
class BadgeProgress {
  final BadgeDef def;
  final int current;
  final bool earned;
  final double progress;

  const BadgeProgress({
    required this.def,
    required this.current,
    required this.earned,
    required this.progress,
  });
}

/// Evaluate every badge in [kBadges] against the supplied [counts]. A missing
/// metric key is treated as 0. Output order mirrors [kBadges].
List<BadgeProgress> evaluateBadges({required Map<BadgeMetric, int> counts}) {
  return [
    for (final def in kBadges)
      () {
        final current = counts[def.metric] ?? 0;
        final threshold = def.threshold < 1 ? 1 : def.threshold;
        return BadgeProgress(
          def: def,
          current: current,
          earned: current >= def.threshold,
          progress: (current / threshold).clamp(0.0, 1.0),
        );
      }(),
  ];
}

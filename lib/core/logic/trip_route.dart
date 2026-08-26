import 'dart:math' as math;

import '../../models/gem.dart';
import '../../models/trip_stop.dart';

/// One itinerary stop resolved to real coordinates plus its map label —
/// feeds both the Overview tab's static map-thumbnail overlay and the
/// full-screen interactive trip map, so the "which stops are plottable, in
/// what order, numbered how" logic lives in exactly one place.
class PlottedStop {
  final TripStop stop;
  final Gem gem;

  /// "day.stopIndexWithinDay", e.g. '1.2' for Day 1's second plottable stop —
  /// scoped to plottable stops only, so a skipped custom/coordinate-less
  /// stop doesn't leave a gap (Day 1's stops are still 1.1, 1.2, 1.3, even
  /// if the itinerary's real second stop that day was an unplottable custom
  /// entry).
  final String label;

  const PlottedStop({required this.stop, required this.gem, required this.label});

  double get lat => gem.latitude!;
  double get lng => gem.longitude!;
}

/// Resolves a stop to its plottable Gem — for a custom stop ([TripStop.isCustom]),
/// that's [_syntheticPlottableGem] (null unless its payload carries real
/// coordinates); for a gem stop, null if the gem itself is missing
/// coordinates. Linear scan over the trip's gem set; fine at this scale (one
/// trip's stops against the catalogue), same as the join summary_sidebar.dart
/// already used before this was extracted.
Gem? _resolveStopGem(TripStop stop, List<Gem> gems) {
  if (stop.isCustom) return _syntheticPlottableGem(stop);
  for (final g in gems) {
    if (g.id == stop.gemId) return g.hasCoords ? g : null;
  }
  return null;
}

/// A custom (non-Gem) stop only plots when its own payload carries real
/// coordinates — set when it was picked from a real Mapbox place
/// (AddStopSheet's nearby/search results) rather than typed as a pure
/// freeform name, which has nowhere to point on a map. Wrapped in a
/// throwaway [Gem] (real id/savedAt aren't meaningful here) so this reuses
/// the exact same marker/route/callout pipeline as a curated-gem stop
/// instead of forking a second "plot a name+coords" path through every
/// [plotStops] consumer (trip_map_dialog.dart, overview_tab.dart).
Gem? _syntheticPlottableGem(TripStop stop) {
  final lat = (stop.customPayload?['lat'] as num?)?.toDouble();
  final lng = (stop.customPayload?['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return Gem(
    id: 'custom-${stop.id}',
    gemName: stop.customTitle ?? 'Custom stop',
    latitude: lat,
    longitude: lng,
    savedAt: DateTime.now(),
  );
}

/// Resolves [orderedStops] (chronological — e.g. TripProvider.allStopsOrdered)
/// against [gems] to the plottable subset, labeled "day.indexWithinDay".
///
/// When [maxPins] is set and the plottable count exceeds it, collapses to one
/// point per day (that day's first plottable stop, labeled "day.1") instead
/// of one per stop — used by the Overview card's small thumbnail so a long
/// trip never renders an unreadable pin cluster. Pass null (the full map
/// modal's choice) for uncapped, full per-stop detail.
List<PlottedStop> plotStops(
  List<TripStop> orderedStops,
  List<Gem> gems, {
  int? maxPins,
}) {
  final resolved = <(TripStop, Gem)>[];
  for (final s in orderedStops) {
    final gem = _resolveStopGem(s, gems);
    if (gem != null) resolved.add((s, gem));
  }
  if (resolved.isEmpty) return const [];

  if (maxPins == null || resolved.length <= maxPins) {
    final indexInDay = <int, int>{};
    return [
      for (final r in resolved)
        PlottedStop(
          stop: r.$1,
          gem: r.$2,
          label:
              '${r.$1.day}.${indexInDay.update(r.$1.day, (v) => v + 1, ifAbsent: () => 1)}',
        ),
    ];
  }

  final firstPerDay = <int, (TripStop, Gem)>{};
  for (final r in resolved) {
    firstPerDay.putIfAbsent(r.$1.day, () => r);
  }
  final days = firstPerDay.keys.toList()..sort();
  return [
    for (final day in days)
      PlottedStop(
        stop: firstPerDay[day]!.$1,
        gem: firstPerDay[day]!.$2,
        label: '$day.1',
      ),
  ];
}

/// Groups plotted stops by trip day, preserving each day's internal
/// chronological order (already guaranteed by [plotStops]'s input). Used to
/// build one polyline segment + one day chip per day, each in that day's
/// own color.
Map<int, List<PlottedStop>> groupPlottedByDay(List<PlottedStop> plotted) {
  final byDay = <int, List<PlottedStop>>{};
  for (final p in plotted) {
    (byDay[p.stop.day] ??= []).add(p);
  }
  return byDay;
}

/// Per-day route colors (ARGB ints, ready for `Color(...)` on the UI side —
/// this file stays Flutter-free per the house convention for lib/core/logic).
/// Indexed by the trip's actual day number (Day 1 is always index 0/blue,
/// Day 3 is always index 2/purple, etc.) rather than by "the Nth day that
/// has stops" — so a color always means the same day number across a trip,
/// even if an earlier day has nothing plotted. Cycles for trips longer than
/// the palette (rare — an 8+ day trip repeats colors).
const List<int> tripDayColors = [
  0xFF2E86FF, // Day 1 — blue
  0xFFFF9F1C, // Day 2 — amber (deliberately not AppTheme.primary — see below)
  0xFF9B5DE5, // Day 3 — purple
  0xFF00BFA6, // Day 4 — teal
  0xFFFF477E, // Day 5 — pink/magenta
  0xFF4CAF50, // Day 6 — green
  0xFF6C757D, // Day 7 — slate gray
  0xFF00B4D8, // Day 8 — cyan
];
// Day 2 uses an amber distinct from AppTheme.primary (#FF6B2B) on purpose:
// reusing the app's exact CTA/accent color as "just one day's route color"
// would make that day's pins read like they mean something special
// (selected/primary action) elsewhere in the app, when they don't.

int colorForTripDay(int day) =>
    tripDayColors[(day - 1) % tripDayColors.length];

/// Bearing (compass degrees, 0 = north, clockwise) from point A to point B —
/// the angle to rotate an "up-pointing" arrow icon so it points from A to B.
/// Flat lat/lng approximation (not geodesic); fine at the city/route scale
/// these arrows render at.
double bearingDegrees(({double lat, double lng}) a, ({double lat, double lng}) b) {
  final lat1 = a.lat * math.pi / 180, lat2 = b.lat * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final theta = math.atan2(y, x);
  return (theta * 180 / math.pi + 360) % 360;
}

/// One direction-arrow placement per consecutive pair of points along a
/// day's route — positioned at the segment midpoint, rotated to point from
/// the first point toward the second. Fewer than 2 points yields no arrows
/// (nothing to point between).
List<({double lat, double lng, double bearing})> routeArrowPoints(
    List<({double lat, double lng})> points) {
  if (points.length < 2) return const [];
  return [
    for (var i = 0; i < points.length - 1; i++)
      (
        lat: (points[i].lat + points[i + 1].lat) / 2,
        lng: (points[i].lng + points[i + 1].lng) / 2,
        bearing: bearingDegrees(points[i], points[i + 1]),
      ),
  ];
}

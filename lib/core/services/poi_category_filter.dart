import 'package:flutter/foundation.dart';
import 'mapbox_tilequery_service.dart';

/// Maps a Mapbox Tilequery POI onto this app's Gem category taxonomy, for
/// screens that show Tilequery results *as if they were gems* — Destination
/// Detail's scoped feed, ListingsScreen's merged grid, and Gem Detail's
/// "Nearby Experiences" rail. Deliberately NOT applied to Trip Builder's Add
/// Stop sheet: that screen's job is "help the user add any real nearby
/// place to their itinerary" (an office, a parking lot, whatever they
/// actually need), not "surface travel-worthy gems" — filtering there would
/// be a regression, not an improvement.
///
/// Returns null when [poi] doesn't cleanly map to one of the 10 categories
/// (`hiking, camping, viewpoint, food, temple, cave, coastal, nature,
/// heritage, landmark`) — government/administrative buildings, utility
/// infrastructure, parking, generic retail/services, lodging, and anything
/// else with no reasonable travel-relevance mapping. Callers must treat
/// null as "exclude from the feed entirely," not "deprioritize" — this is
/// an allowlist, not a ranking signal.
///
/// Checked first against [NearbyPoi.maki] (Mapbox's icon identifier — a
/// fixed, locale-independent taxonomy), then against [NearbyPoi.category]
/// (Tilequery's human-readable type/class label, lowercased) for results
/// whose maki is `'marker'` or otherwise unmapped — `'marker'` is
/// Tilequery's generic fallback icon, used across many otherwise-unrelated
/// categories (government buildings, offices, apartments, generic
/// buildings all shared it in real samples), so it carries no signal on
/// its own.
///
/// Memorial/monument decision (confirmed with the product owner,
/// 2026-08-28): included, mapped to `heritage`. Real Tilequery data pulled
/// for Ho Chi Minh City turned up a Ho Chi Minh memorial/statue
/// (`class: historic, type: Memorial, maki: monument`) alongside the
/// government offices and parking lots this filter excludes — travelers do
/// genuinely seek these out, unlike the excluded categories.
String? mapPoiToGemCategory(NearbyPoi poi) {
  final byMaki = _makiToCategory[poi.maki];
  if (byMaki != null) return byMaki;

  final type = poi.category?.trim().toLowerCase();
  if (type != null && type.isNotEmpty) {
    final byType = _typeToCategory[type];
    if (byType != null) return byType;
  }

  _recordUnmapped(poi);
  return null;
}

/// Filters [pois] down to the ones [mapPoiToGemCategory] resolves to one of
/// the 10 Gem categories — the actual allowlist callers apply.
List<NearbyPoi> filterTravelRelevantPois(List<NearbyPoi> pois) =>
    pois.where((p) => mapPoiToGemCategory(p) != null).toList();

// Keyed by Mapbox's maki icon identifier — see NearbyPoi.iconForMaki for
// the full set this app already recognizes for display. Anything NOT
// listed here — 'bank', 'town-hall', 'parking', 'parking-garage',
// 'hospital', 'pharmacy', 'school', 'college', 'lodging', 'airport', 'bus',
// 'rail', 'rail-metro', 'shop', 'shoe', 'clothing-store', 'grocery',
// 'commercial', 'zoo', ... — is deliberately excluded, not merely omitted.
const Map<String, String> _makiToCategory = {
  'restaurant': 'food',
  'fast-food': 'food',
  'cafe': 'food',
  'bar': 'food',
  'beer': 'food',
  'museum': 'heritage',
  'attraction': 'heritage',
  'monument': 'heritage',
  'memorial': 'heritage',
  'park': 'nature',
  'garden': 'nature',
  'park-alt1': 'nature',
  'mountain': 'nature',
  'beach': 'coastal',
  'religious-christian': 'temple',
  'religious-muslim': 'temple',
  'religious-jewish': 'temple',
  'religious-buddhist': 'temple',
  'religious-hindu': 'temple',
  'place-of-worship': 'temple',
};

/// Fallback keyed by Tilequery's human-readable type/class
/// ([NearbyPoi.category], lowercased) — for results whose maki is
/// 'marker' or otherwise unmapped above. Every key here was seen directly
/// in real Tilequery API responses pulled for Hanoi (21.0278,105.8342) and
/// Ho Chi Minh City (10.7769,106.7009) on 2026-08-28, radius 5000m — not
/// guessed. Excluded-on-purpose values seen in that same pull, for
/// reference (not travel-relevant, so not listed as keys): Government,
/// Townhall, Commercial (UBND grounds), Research, Military, Office,
/// Apartments, Parking, Bank, Pharmacy, Kindergarten, Hotel, Supermarket,
/// Convenience, and every generic "Yes"-typed building.
const Map<String, String> _typeToCategory = {
  // food_and_drink class
  'restaurant': 'food',
  'cafe': 'food',
  'pub': 'food',
  'fast food': 'food',
  // religion class
  'place of worship': 'temple',
  // park_like class ('Playground' seen in the same class, deliberately
  // excluded — not a travel destination in its own right)
  'park': 'nature',
  'garden': 'nature',
  // historic class — the confirmed memorial/monument decision above
  'memorial': 'heritage',
  'monument': 'heritage',
  // arts_and_entertainment class
  'attraction': 'heritage',
};

/// Distinct (category, maki) pairs seen that didn't map to any of the 10
/// Gem categories — collected at runtime, not persisted, so the tables
/// above can be reviewed and extended later without re-deriving this from
/// scratch. Nothing else reads this yet; it exists for that future review,
/// per the explicit "log rather than silently drop" requirement.
final Set<String> unmappedPoiSignatures = <String>{};

void _recordUnmapped(NearbyPoi poi) {
  final sig = '${poi.category ?? '(no category)'} / maki:${poi.maki ?? '(none)'}';
  if (unmappedPoiSignatures.add(sig)) {
    debugPrint('poi_category_filter: unmapped POI category — $sig');
  }
}

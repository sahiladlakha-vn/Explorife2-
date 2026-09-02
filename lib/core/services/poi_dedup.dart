import 'package:geolocator/geolocator.dart';
import '../../models/gem.dart';
import 'mapbox_tilequery_service.dart';

/// How close two INDEPENDENTLY-geocoded points must be to plausibly be the
/// same physical place, for suppressing a Tilequery POI that's really just
/// the auto-pulled duplicate of a curated Gem.
///
/// Deliberately looser than the 15m self-exclusion threshold
/// gem_detail_screen.dart uses for "is this POI literally the gem I'm
/// viewing" — that compares a POI's coordinates against the SAME gem's own
/// coordinates, so both numbers come from one source and agree tightly.
/// Here the two coordinates come from two independent geocodes: a curated
/// Gem's coordinates (resolved from a free-text address via Mapbox
/// forward-geocoding, in gem-sheet-sync.gs) and a Tilequery POI's
/// coordinates (Mapbox's own POI tileset) — these can legitimately disagree
/// by tens of meters for the exact same real-world building depending on
/// how precise the source address was. 30m is the upper end of the range
/// suggested in this app's own earlier POI work; checked against real
/// Tilequery data pulled for Hanoi's Temple of Literature area (2026-09-03,
/// 21.0278,105.8342, radius 5000m): the closest two DIFFERENT real places
/// in that pull sit ~15-20m apart (a Cafe and a Park entrance), so 30m
/// stays under that gap while still covering realistic geocoding drift.
const dedupRadiusMeters = 30.0;

/// Whether [gem] is plausibly the same physical place as a candidate
/// location described by [name]/[lat]/[lng] — requires BOTH close
/// proximity AND a name match, so two merely-adjacent but genuinely
/// different places (e.g. a cafe next to a monument, both well within
/// 30m) don't get wrongly conflated just because proximity alone would
/// allow it. The shared core behind [sameRealPlace] (Tilequery POI dedup)
/// and Attraction's own "this looks like an existing place" check at
/// listing-creation time (attraction_form_screen.dart) — one matching
/// rule for "is this the same real place as a Gem," not two.
bool placeLikelyMatchesGem(
  Gem gem, {
  required String name,
  required double lat,
  required double lng,
}) {
  if (!gem.hasCoords) return false;
  final distance =
      Geolocator.distanceBetween(gem.latitude!, gem.longitude!, lat, lng);
  if (distance > dedupRadiusMeters) return false;
  return placeNamesLikelyMatch(gem.gemName, name);
}

/// Whether [gem] and [poi] are plausibly the exact same physical place —
/// see [placeLikelyMatchesGem].
bool sameRealPlace(Gem gem, NearbyPoi poi) =>
    placeLikelyMatchesGem(gem, name: poi.name, lat: poi.lat, lng: poi.lng);

/// The first Gem in [gems] that plausibly describes the same real place as
/// [name]/[lat]/[lng], or null if none do — backs Attraction's "this looks
/// like an existing place — link it?" prompt at listing-creation time.
/// Not a guarantee (a genuine coincidence — two differently-run cafes 20m
/// apart with similar names — is possible, however unlikely), which is
/// exactly why this surfaces as a confirm-or-decline prompt to the
/// business owner rather than an automatic silent link.
Gem? findLikelyGemMatch(
  List<Gem> gems, {
  required String name,
  required double lat,
  required double lng,
}) {
  for (final gem in gems) {
    if (placeLikelyMatchesGem(gem, name: name, lat: lat, lng: lng)) return gem;
  }
  return null;
}

/// Drops any [pois] that plausibly duplicate a place already covered by
/// [gems] (see [sameRealPlace]) — so a curated Gem never shows up twice in
/// the same feed: once as itself, once again as the raw Tilequery version
/// of the same spot. Returns [pois] unchanged when there's nothing to check
/// against.
List<NearbyPoi> excludeDuplicatesOf(List<NearbyPoi> pois, List<Gem> gems) {
  if (gems.isEmpty || pois.isEmpty) return pois;
  return pois.where((p) => !gems.any((g) => sameRealPlace(g, p))).toList();
}

/// Folds Vietnamese and common Latin diacritics to their base letter —
/// this app's Tilequery results are frequently in Vietnamese with full
/// tone marks (e.g. "Khuê Văn Các"), while a curated Gem's name is often
/// typed by a content editor without them ("Khue Van Cac"). No existing
/// package in this repo does Unicode NFD normalization; this hand-written
/// table covers the actual Vietnamese alphabet (all 6 tone marks × the
/// modified base vowels ăâêôơư, plus đ) rather than pulling in a dependency
/// for a fixed, known-size alphabet.
const Map<String, String> _diacriticFold = {
  'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
  'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
  'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
  'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
  'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
  'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
  'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
  'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
  'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
  'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
  'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
  'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  'đ': 'd',
  // Common non-Vietnamese Latin accents — this app's Tilequery calls also
  // return places named in other languages (French/Spanish loanwords etc.).
  'ñ': 'n', 'ç': 'c', 'ü': 'u', 'ö': 'o', 'ä': 'a', 'ß': 's',
};

/// Lowercase, fold diacritics, drop anything that isn't a letter/digit,
/// collapse whitespace. Two names that only differ by accents, case, or
/// punctuation normalize to the exact same string.
String _normalizePlaceName(String s) {
  final buffer = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_diacriticFold[ch] ?? ch);
  }
  final folded = buffer.toString().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True when [a] and [b] are close enough (after folding accents/case/
/// punctuation) to plausibly name the same place: an exact match once
/// normalized, every word of the shorter name appearing as a WHOLE word in
/// the longer one (only when the shorter name has 2+ words, so a single
/// generic word like "Park" doesn't match "Parking Garage"), or at least
/// half the smaller name's words appearing in the other.
bool placeNamesLikelyMatch(String a, String b) {
  final na = _normalizePlaceName(a);
  final nb = _normalizePlaceName(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;

  final wordsA = na.split(' ').where((w) => w.isNotEmpty).toSet();
  final wordsB = nb.split(' ').where((w) => w.isNotEmpty).toSet();
  if (wordsA.isEmpty || wordsB.isEmpty) return false;

  final smallerWords = wordsA.length <= wordsB.length ? wordsA : wordsB;
  final biggerWords = wordsA.length <= wordsB.length ? wordsB : wordsA;

  if (smallerWords.length >= 2 && smallerWords.every(biggerWords.contains)) {
    return true;
  }

  final overlap = wordsA.intersection(wordsB).length;
  return overlap / smallerWords.length >= 0.5;
}

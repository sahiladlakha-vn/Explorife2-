import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/gem.dart';
import '../models/gem_draft.dart';
import '../repositories/gem_repository.dart';

/// Lifecycle of the gem list load — makes loading/error first-class rather than
/// implied by a bool + nullable string.
enum GemStatus { initial, loading, ready, error }

/// How the discovery feed orders gems. [recent] is the natural order (newest
/// first, matching the repository fetch + realtime prepend); [name] is a stable
/// A→Z sort. Drives the sheet's sort button.
enum GemSort { recent, name }

/// Outcome of a publish attempt, so the view can render precise feedback
/// (e.g. "saved, but the photo failed") without re-deriving anything.
class GemPublishResult {
  final bool success;

  /// A photo was chosen but its upload failed; the gem was still saved.
  final bool photoFailed;
  final Gem? gem;
  final String? error;

  const GemPublishResult({
    required this.success,
    this.photoFailed = false,
    this.gem,
    this.error,
  });
}

/// Single source of truth for gem state. Owns the in-memory list, the selected
/// category filter, and load/publish status. Talks **only** to [GemRepository]
/// — it has no Supabase import — and listens to the repository's realtime
/// streams to keep the list live.
class GemProvider extends ChangeNotifier {
  GemProvider({GemRepository? repository})
      : _repo = repository ?? GemRepository() {
    _initRealtime();
    _fetchGems();
  }

  final GemRepository _repo;
  StreamSubscription<Gem>? _insertSub;
  StreamSubscription<String>? _deleteSub;

  List<Gem> _gems = [];
  GemStatus _status = GemStatus.initial;
  String? _error;
  String _selectedCategory = 'all';
  GemSort _sort = GemSort.recent;

  // Saves are backed by the `gem_saves` join table. [_savedIds] is the single
  // in-memory truth the heart-toggle reads; [_savedGems] is the hydrated card
  // list the Saved tab renders, kept in lockstep with it. Both are seeded by
  // [loadSaved] and mutated together on every [toggleSave].
  final Set<String> _savedIds = <String>{};
  List<Gem> _savedGems = [];
  GemStatus _savedStatus = GemStatus.initial;
  String? _savedError;
  bool _savedLoaded = false;

  List<Gem> get gems => _filtered;
  List<Gem> get allGems => _gems;
  GemStatus get status => _status;
  bool get loading => _status == GemStatus.loading;
  bool get hasError => _status == GemStatus.error;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  GemSort get sort => _sort;

  /// The signed-in user's saved gems, newest save first — what the Saved tab
  /// renders. Populated by [loadSaved] and kept current by [toggleSave].
  List<Gem> get savedGems => _savedGems;
  GemStatus get savedStatus => _savedStatus;
  bool get savedLoading => _savedStatus == GemStatus.loading;
  bool get savedHasError => _savedStatus == GemStatus.error;
  String? get savedError => _savedError;

  /// Applies the active category filter + sort to [source]. Factored so the
  /// global feed (map markers) and the focus-scoped sheet feed share one
  /// ordering codepath rather than duplicating the sort.
  List<Gem> _sortAndFilter(Iterable<Gem> source) {
    final base = _selectedCategory == 'all'
        ? source.toList()
        : source.where((g) => g.category == _selectedCategory).toList();
    switch (_sort) {
      case GemSort.recent:
        return base; // already newest-first from fetch + realtime prepend.
      case GemSort.name:
        return base
          ..sort((a, b) =>
              a.gemName.toLowerCase().compareTo(b.gemName.toLowerCase()));
    }
  }

  /// Global feed (every loaded gem, category-filtered + sorted) — drives the
  /// MAP MARKERS, which stay global so panning/zooming always reveals gems
  /// beyond any searched area.
  List<Gem> get _filtered => _sortAndFilter(_gems);

  List<Gem> get mappableGems => _filtered.where((g) => g.hasCoords).toList();

  // ───────── featured rail (Home tab) ─────────

  /// How many cards the Home Featured rail shows.
  static const int kFeaturedCount = 8;

  /// A gem saved within this window wears the TRENDING pill.
  static const int kTrendingWindowDays = 14;

  /// Below this many photo-bearing gems, the rail falls back to ALL gems so it's
  /// never sparse at the current ~46-gem / near-zero-save scale.
  static const int kFeaturedMinPhotos = 3;

  /// Recency-equivalent boost (in days) a photo is worth, so photo gems lead the
  /// rail and cards rarely render a fallback image.
  static const double kFeaturedPhotoBoost = 30.0;

  /// Whether [g] was saved recently enough to be "trending".
  bool isTrending(Gem g) =>
      DateTime.now().difference(g.savedAt).inDays <= kTrendingWindowDays;

  /// The single ranking seam: recency-first (newer ranks higher), biased toward
  /// gems with a photo. When a real save_count/rating column lands, add
  /// `+ g.saveCount * kSaveWeight` here and the rail becomes true trending for
  /// free — callers don't change.
  double _featuredScore(Gem g) {
    final recency = -DateTime.now().difference(g.savedAt).inDays.toDouble();
    final hasPhoto = g.photoUrl != null && g.photoUrl!.isNotEmpty;
    return recency + (hasPhoto ? kFeaturedPhotoBoost : 0.0);
  }

  /// The Home Featured rail's gems: ranked by [_featuredScore], capped at
  /// [kFeaturedCount]. Reads the FULL list (not the category filter) on purpose
  /// — Home's pills are still Destination categories (deferred). Prefers gems
  /// with a photo, falling back to all gems when too few have one so the rail is
  /// never empty.
  List<Gem> get featured {
    final withPhoto = _gems
        .where((g) => g.photoUrl != null && g.photoUrl!.isNotEmpty)
        .toList();
    final pool = withPhoto.length >= kFeaturedMinPhotos
        ? withPhoto
        : List<Gem>.of(_gems);
    pool.sort((a, b) => _featuredScore(b).compareTo(_featuredScore(a)));
    return pool.take(kFeaturedCount).toList();
  }

  // ───────── map viewport (drives the floating deck) ─────────

  /// Current map bounds, pushed by the host on camera idle. The MARKERS stay
  /// global (pan-to-discover); only the floating DECK is clipped to these
  /// bounds, so it never shows a card for a gem the user can't see as a pin.
  /// Null until the first idle — the deck then falls back to the global set.
  double? _viewW, _viewS, _viewE, _viewN;
  bool get _hasViewport => _viewW != null;

  /// Stores the current map bounds (west/south/east/north). Notifies only when
  /// the bounds actually move, so a settled pan re-filters the deck without a
  /// rebuild storm on no-op idles. Assumes NON-WRAPPING bounds (W ≤ E); the
  /// app's regions never straddle the antimeridian.
  void setViewport(double west, double south, double east, double north) {
    if (_viewW == west &&
        _viewS == south &&
        _viewE == east &&
        _viewN == north) {
      return;
    }
    _viewW = west;
    _viewS = south;
    _viewE = east;
    _viewN = north;
    notifyListeners();
  }

  /// The anchor the deck's distance SORT and its distance PILL both read, so a
  /// card's position always matches the number printed on it: the user's
  /// location when known, else the viewport centre (a denied permission still
  /// yields a stable nearest-first order and a real number on every card). Null
  /// only before the first idle with no known location.
  (double, double)? deckAnchor({double? userLat, double? userLng}) {
    if (userLat != null && userLng != null) return (userLat, userLng);
    if (!_hasViewport) return null;
    return ((_viewS! + _viewN!) / 2, (_viewW! + _viewE!) / 2);
  }

  /// The floating deck's gem set: [mappableGems] clipped to the current viewport
  /// bounds and sorted by distance ASCENDING from [deckAnchor] (nearest first).
  /// Before the first idle (no bounds yet) it falls back to the global set so
  /// the deck isn't empty on first paint. // assumes non-wrapping bounds (W ≤ E)
  List<Gem> deckGems({double? userLat, double? userLng}) {
    final all = mappableGems;
    if (!_hasViewport) return all;
    final inBounds = all
        .where((g) =>
            g.latitude! >= _viewS! &&
            g.latitude! <= _viewN! &&
            g.longitude! >= _viewW! &&
            g.longitude! <= _viewE!)
        .toList();
    final anchor = deckAnchor(userLat: userLat, userLng: userLng);
    if (anchor != null) {
      inBounds.sort((a, b) => _distanceMeters(
              anchor.$1, anchor.$2, a.latitude!, a.longitude!)
          .compareTo(_distanceMeters(
              anchor.$1, anchor.$2, b.latitude!, b.longitude!)));
    }
    return inBounds;
  }

  // ───────── active area (scopes the SHEET feed + chip counts) ─────────

  /// The bounding box the SHEET feed (list + count + chips) is scoped to — a
  /// real place bbox (W/S/E/N), NOT a radius, so a whole city fits. Set at launch
  /// from the reverse-geocoded home city, and on each explicit search from the
  /// chosen place's bbox. Panning does NOT change it. Null only before the first
  /// area resolves. The MARKERS stay global (pan-to-discover), so the count never
  /// claims hidden spots over a region the map has left.
  double? _areaW, _areaS, _areaE, _areaN;
  String? _areaLabel;
  bool get hasActiveArea => _areaW != null;
  String? get activeAreaLabel => _areaLabel;

  /// The active-area bbox as `(west, south, east, north)`, or null when unset.
  /// Exposed so the host can test the live viewport centre against it to drive
  /// the "Search this area" affordance.
  (double, double, double, double)? get activeAreaBounds =>
      hasActiveArea ? (_areaW!, _areaS!, _areaE!, _areaN!) : null;

  /// The live viewport centre, or null before the first idle. Pairs with
  /// [activeAreaBounds] so the host can decide when the user has panned away.
  (double, double)? get viewportCenter =>
      _hasViewport ? ((_viewS! + _viewN!) / 2, (_viewW! + _viewE!) / 2) : null;

  /// Sets the active area to the bbox [west]/[south]/[east]/[north] with an
  /// optional [label] for the header. No-ops when the box is unchanged so a
  /// re-resolve of the same city doesn't churn the feed.
  void setActiveArea(double west, double south, double east, double north,
      {String? label}) {
    if (_areaW == west &&
        _areaS == south &&
        _areaE == east &&
        _areaN == north &&
        _areaLabel == label) {
      return;
    }
    _areaW = west;
    _areaS = south;
    _areaE = east;
    _areaN = north;
    _areaLabel = label;
    notifyListeners();
  }

  /// Clears the active area so the feed spans every loaded gem again. No-op when
  /// nothing is set.
  void clearActiveArea() {
    if (!hasActiveArea) return;
    _areaW = _areaS = _areaE = _areaN = null;
    _areaLabel = null;
    notifyListeners();
  }

  /// The anchor the sheet's distance SORT and its distance PILL both read, so a
  /// row's position always matches the number printed on it: the user's location
  /// when known, else the active-area centre. Null only when neither is known.
  (double, double)? feedAnchor({double? userLat, double? userLng}) {
    if (userLat != null && userLng != null) return (userLat, userLng);
    if (hasActiveArea) return ((_areaS! + _areaN!) / 2, (_areaW! + _areaE!) / 2);
    return null;
  }

  /// Loaded gems inside the active-area bbox (or all loaded gems when no area is
  /// set). The single source the sheet's list AND counts draw from, so they
  /// agree. // assumes non-wrapping bounds (W < E)
  Iterable<Gem> get _feedScoped {
    if (!hasActiveArea) return _gems;
    return _gems.where((g) =>
        g.hasCoords &&
        g.latitude! >= _areaS! &&
        g.latitude! <= _areaN! &&
        g.longitude! >= _areaW! &&
        g.longitude! <= _areaE!);
  }

  /// The sheet's list: area-scoped, category-filtered, sorted, coords-only, then
  /// re-ordered nearest-first off [feedAnchor] so the closest gem leads.
  List<Gem> feedGems({double? userLat, double? userLng}) {
    final list =
        _sortAndFilter(_feedScoped).where((g) => g.hasCoords).toList();
    final anchor = feedAnchor(userLat: userLat, userLng: userLng);
    if (anchor != null) {
      list.sort((a, b) => _distanceMeters(
              anchor.$1, anchor.$2, a.latitude!, a.longitude!)
          .compareTo(_distanceMeters(
              anchor.$1, anchor.$2, b.latitude!, b.longitude!)));
    }
    return list;
  }

  /// The map-eligible universe: every loaded gem with coordinates, IGNORING the
  /// active category filter. The denominator the GLOBAL marker counts draw from.
  List<Gem> get _mappableUniverse => _gems.where((g) => g.hasCoords).toList();

  /// Global mappable-gem count for [category] ('all' = the whole universe). Used
  /// by callers that reason about every pin on the map regardless of search.
  int mappableCount(String category) => category == 'all'
      ? _mappableUniverse.length
      : _mappableUniverse.where((g) => g.category == category).length;

  /// Area-scoped per-category count for the sheet. By construction
  /// `feedCount(selectedCategory) == feedGems().length`, so the header total, the
  /// chip numbers and the rendered list always agree with each other.
  int feedCount(String category) {
    final base = _feedScoped.where((g) => g.hasCoords);
    return category == 'all'
        ? base.length
        : base.where((g) => g.category == category).length;
  }

  // ───────── nearby (Home "Gems Near You" — PURE, screen-local) ─────────

  /// Gems ranked nearest-first from ([lat], [lng]), capped at [limit]. Reads
  /// [_gems] only — no `_selectedCategory` mutation, no notify — so the Home
  /// rail can sort by location without ever filtering the shared Map feed.
  /// Falls back to the newest gems (which [_gems] already is, saved_at desc)
  /// when location is unknown or no gem has coordinates, so the section is
  /// NEVER empty for want of a fix.
  ///
  /// SEAM: at the ≤100-row client cache an in-memory haversine sort is fine;
  /// swap to a PostGIS / server-side distance query here when it outgrows that.
  List<Gem> nearbyGems(double? lat, double? lng, {int limit = 8}) {
    final coord = _gems.where((g) => g.hasCoords).toList();
    if (lat == null || lng == null || coord.isEmpty) {
      return _gems.take(limit).toList();
    }
    final origin = LatLng(lat, lng);
    const distance = Distance();
    coord.sort((a, b) => distance(origin, LatLng(a.latitude!, a.longitude!))
        .compareTo(distance(origin, LatLng(b.latitude!, b.longitude!))));
    return coord.take(limit).toList();
  }

  /// Great-circle distance in KILOMETRES from ([lat], [lng]) to [g], or null
  /// when the origin is unknown or [g] has no coordinates. [Distance] returns
  /// metres, so divide by 1000. Pure — used only to label the row that
  /// [nearbyGems] already ordered.
  double? distanceKmFrom(double? lat, double? lng, Gem g) {
    if (lat == null || lng == null || !g.hasCoords) return null;
    const distance = Distance();
    return distance(LatLng(lat, lng), LatLng(g.latitude!, g.longitude!)) / 1000;
  }

  // ───────── search (Search tab — PURE, screen-local) ─────────

  /// Pure substring search over the loaded gems. Reads [_gems] directly and
  /// neither mutates `_selectedCategory`/`_sort` nor calls [notifyListeners],
  /// so the Search screen can drive it from local setState WITHOUT filtering the
  /// shared Map/Home feeds. When [category] != 'all' the list is narrowed to
  /// that gem category first; an empty [query] then returns the whole
  /// category slice (so picking a category alone lists its gems). The text
  /// match is case-insensitive across name / location / category / description.
  ///
  /// SEAM: at the ≤100-row client cache this is correct; swap to a Supabase
  /// `.ilike` / full-text query here when the catalog outgrows the cache.
  List<Gem> search({String query = '', String category = 'all'}) {
    final base = category == 'all'
        ? _gems
        : _gems.where((g) => g.category == category).toList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Gem>.of(base);
    return base.where((g) {
      final haystack = [
        g.gemName,
        g.gemLocation ?? '',
        g.category ?? '',
        g.description ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  /// Derived "popular" search terms for the Search screen's suggestion chips:
  /// the most common gem categories and locations across [_gems], ordered by
  /// frequency, deduped case-insensitively, and capped at 6. Falls back to a
  /// curated pair when the catalogue is too sparse to derive two terms. Pure
  /// getter — no state, no notify. Terms are display-cased.
  List<String> get popularTerms {
    final counts = <String, int>{}; // lower-cased term → frequency
    final display = <String, String>{}; // lower-cased term → display form
    void tally(String? raw) {
      final t = raw?.trim();
      if (t == null || t.isEmpty) return;
      final key = t.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => t[0].toUpperCase() + t.substring(1));
    }

    for (final g in _gems) {
      tally(g.category);
      tally(g.gemLocation);
    }
    final terms = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final ranked = terms.map((k) => display[k]!).take(6).toList();
    return ranked.length >= 2 ? ranked : const ['Hiking', 'Coastal'];
  }

  /// Great-circle distance in metres (Haversine). Kept private + pure here so
  /// the focus filter needs no Geolocator dependency in the state layer.
  static double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // mean Earth radius, metres
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void _initRealtime() {
    _repo.connectRealtime();
    _insertSub = _repo.gemInserts.listen(_upsert);
    _deleteSub = _repo.gemDeletes.listen(_removeById);
  }

  Future<void> _fetchGems() async {
    _status = GemStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _gems = await _repo.fetchGems();
      _status = GemStatus.ready;
    } catch (e) {
      _error = e.toString();
      _status = GemStatus.error;
      debugPrint('GemProvider fetch error: $e');
    }
    notifyListeners();
  }

  /// Insert-or-replace by id so a realtime echo of a row we already added (or a
  /// duplicate insert event) never double-lists the gem.
  void _upsert(Gem gem) {
    final idx = _gems.indexWhere((g) => g.id == gem.id);
    if (idx >= 0) {
      final next = [..._gems];
      next[idx] = gem;
      _gems = next;
    } else {
      _gems = [gem, ..._gems];
    }
    notifyListeners();
  }

  void _removeById(String id) {
    _gems = _gems.where((g) => g.id != id).toList();
    notifyListeners();
  }

  void selectCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  void setSort(GemSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    notifyListeners();
  }

  // ───────── saves (optimistic, gem_saves-backed) ─────────

  /// Whether [id] is currently marked saved. Drives the card's save toggle.
  bool isSaved(String id) => _savedIds.contains(id);

  /// Hydrates [_savedIds] + [_savedGems] from the `gem_saves` table. Guarded and
  /// idempotent like the trip fetches: a no-op once loaded unless [force] is
  /// set, and it won't stack a second in-flight fetch. Callers can fire it
  /// on-mount without gating on their own flag.
  Future<void> loadSaved({bool force = false}) async {
    if (_savedLoaded && !force) return;
    if (_savedStatus == GemStatus.loading) return;
    _savedStatus = GemStatus.loading;
    _savedError = null;
    notifyListeners();
    try {
      final saved = await _repo.fetchSavedGems();
      _savedGems = saved;
      _savedIds
        ..clear()
        ..addAll(saved.map((g) => g.id));
      _savedStatus = GemStatus.ready;
      _savedLoaded = true;
    } catch (e) {
      _savedError = e.toString();
      _savedStatus = GemStatus.error;
      debugPrint('GemProvider.loadSaved error: $e');
    }
    notifyListeners();
  }

  /// Toggles the saved state for [gem] optimistically: the in-memory set and the
  /// hydrated [_savedGems] card list flip together and listeners are notified
  /// immediately, then the repository persists to `gem_saves`. If persistence
  /// fails we roll both back and re-notify, so the toggle never lies about
  /// persisted state and the Saved tab never shows a phantom (or missing) card.
  Future<void> toggleSave(Gem gem) async {
    final wasSaved = _savedIds.contains(gem.id);
    if (wasSaved) {
      _savedIds.remove(gem.id);
      _savedGems = _savedGems.where((g) => g.id != gem.id).toList();
    } else {
      _savedIds.add(gem.id);
      _savedGems = [gem, ..._savedGems];
    }
    notifyListeners();
    try {
      if (wasSaved) {
        await _repo.unsaveGem(gem.id);
      } else {
        await _repo.saveGem(gem.id);
      }
    } catch (e) {
      // Roll back on failure so the toggle never lies about persisted state.
      if (wasSaved) {
        _savedIds.add(gem.id);
        _savedGems = [gem, ..._savedGems];
      } else {
        _savedIds.remove(gem.id);
        _savedGems = _savedGems.where((g) => g.id != gem.id).toList();
      }
      debugPrint('GemProvider.toggleSave error: $e');
      notifyListeners();
    }
  }

  Future<Gem?> fetchById(String id) => _repo.fetchById(id);

  Future<List<Gem>> fetchRelated(String category, String excludeId) =>
      _repo.fetchRelated(category, excludeId);

  /// Publishes an approved [draft]: uploads the optional photo, inserts the
  /// row, and optimistically adds the persisted gem to the list (the realtime
  /// echo is deduped by [_upsert]). Never throws — failures come back in the
  /// returned [GemPublishResult].
  Future<GemPublishResult> publish(
    GemDraft draft, {
    required String userId,
    XFile? photo,
  }) async {
    try {
      var photoFailed = false;
      String? photoUrl;
      if (photo != null) {
        final urls = await _repo.uploadPhotos(userId, [photo]);
        if (urls.isEmpty) {
          photoFailed = true;
        } else {
          photoUrl = urls.first;
        }
      }
      final gem = await _repo.create(draft, userId: userId, photoUrl: photoUrl);
      _upsert(gem);
      return GemPublishResult(
          success: true, photoFailed: photoFailed, gem: gem);
    } catch (e) {
      debugPrint('GemProvider.publish error: $e');
      return GemPublishResult(success: false, error: e.toString());
    }
  }

  Future<void> refresh() => _fetchGems();

  @override
  void dispose() {
    _insertSub?.cancel();
    _deleteSub?.cancel();
    _repo.dispose();
    super.dispose();
  }
}

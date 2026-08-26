// lib/providers/destination_provider.dart
//
// Real-data destination search, backed by Mapbox Search Box (POI/place
// search) — replaces the old in-memory seed list entirely. Search Box is
// query-triggered (there's no "give me N interesting places" mode the way a
// preloaded catalogue has), so this is now a search-as-you-type provider,
// not a preload-then-filter list like before: state is "what did the user
// type" and "what did that return," not "the whole catalogue, filtered
// client-side."

import 'package:flutter/foundation.dart';
import '../core/services/mapbox_search_service.dart';
import '../models/destination.dart';

enum DestinationStatus { initial, loading, ready, error }

class DestinationProvider extends ChangeNotifier {
  DestinationProvider({MapboxSearchService? search})
      : _search = search ?? MapboxSearchService();

  final MapboxSearchService _search;

  DestinationStatus _status = DestinationStatus.initial;
  String? _error;
  String _query = '';
  List<Destination> _results = [];

  // Saves are local-only (no destinations table exists — these aren't Gems),
  // keyed by mapbox_id so a save survives a fresh search returning the same
  // place again.
  final Set<String> _savedIds = {};

  // ── status getters ──
  DestinationStatus get status => _status;
  bool get isLoading => _status == DestinationStatus.loading;
  bool get hasError => _status == DestinationStatus.error;
  String? get error => _error;

  // ── search state ──
  String get query => _query;
  List<Destination> get results => _results;
  List<Destination> get saved =>
      _results.where((d) => _savedIds.contains(d.id)).toList();

  /// Runs a fresh search, replacing [results]. Callers should debounce their
  /// own input (see DestinationSearchScreen) — this fires the request
  /// immediately on every call. Clearing the query (or typing fewer than 2
  /// characters) resets to the empty initial state rather than erroring.
  Future<void> search(String query) async {
    _query = query;
    final q = query.trim();
    if (q.length < 2) {
      _results = [];
      _status = DestinationStatus.initial;
      notifyListeners();
      return;
    }

    _status = DestinationStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final suggestions = await _search.suggest(q, types: 'poi,place');
      _results = suggestions
          .map((s) => Destination.fromSuggestion(s,
              isSaved: _savedIds.contains(s.mapboxId)))
          .toList();
      _status = DestinationStatus.ready;
    } catch (_) {
      _error = 'Check your connection and try again.';
      _status = DestinationStatus.error;
    }
    notifyListeners();
  }

  Future<void> retrySearch() => search(_query);

  /// Resolves a search result's real coordinates for the detail page — the
  /// `/suggest` step ([search]) never returns them (see Destination's doc
  /// comment on [Destination.hasCoords]). Returns null on failure; the caller
  /// (DestinationDetailScreen) shows its own error state rather than this
  /// provider tracking a second status machine for one-off resolves.
  Future<Destination?> resolve(String mapboxId) async {
    final details = await _search.retrieve(mapboxId);
    if (details == null) return null;
    return Destination.fromPlaceDetails(details,
        isSaved: _savedIds.contains(mapboxId));
  }

  void toggleSave(String id) {
    if (!_savedIds.add(id)) _savedIds.remove(id);
    // Keep any already-loaded result's isSaved flag in sync so re-rendering
    // the current search results reflects the toggle immediately.
    for (final d in _results) {
      if (d.id == id) d.isSaved = _savedIds.contains(id);
    }
    notifyListeners();
  }

  bool isSaved(String id) => _savedIds.contains(id);
}

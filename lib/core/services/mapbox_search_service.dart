import 'dart:convert';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// One autocomplete candidate from Search Box's `/suggest` step — no
/// coordinates yet. Mapbox's session-token billing charges once per session
/// (any number of suggest calls + one retrieve), not per suggestion, so
/// resolving coordinates for every candidate up front would be both wasted
/// work and wasted spend — only [MapboxSearchService.retrieve] on the one the
/// user actually picks does that.
class PlaceSuggestion {
  final String mapboxId;
  final String name;
  final String placeFormatted;

  /// Mapbox's own POI category (e.g. "restaurant", "hotel") — a different,
  /// much larger taxonomy than this app's fixed 8 Gem categories. Null for
  /// non-POI results (a plain place/address suggestion).
  final String? category;

  const PlaceSuggestion({
    required this.mapboxId,
    required this.name,
    required this.placeFormatted,
    this.category,
  });
}

/// A fully-resolved place from Search Box's `/retrieve` step — has real
/// coordinates, unlike [PlaceSuggestion].
class PlaceDetails {
  final String mapboxId;
  final String name;
  final String placeFormatted;
  final String? category;
  final double lat;
  final double lng;

  const PlaceDetails({
    required this.mapboxId,
    required this.name,
    required this.placeFormatted,
    this.category,
    required this.lat,
    required this.lng,
  });
}

/// Wraps Mapbox's **Search Box API** — free-text POI/place search with
/// autocomplete (restaurants, hotels, attractions, landmarks). Distinct from
/// [GeocodingService] (Search Geocoding v6: city/region/address lookup only,
/// no POI search) — the two APIs solve different problems and this app now
/// uses both for what each is actually good at.
///
/// Session-token billing: Mapbox bills one "session" (any number of
/// [suggest] calls, plus the one [retrieve] that resolves a choice) as a
/// single unit — much cheaper than per-call billing for a search-as-you-type
/// flow. [_session] is generated lazily on the first [suggest] of a session
/// and reset after [retrieve] closes it out, per Mapbox's documented session
/// lifecycle. A caller that never retrieves (user abandons the search) just
/// lets the token go stale; the next [suggest] mints a fresh one.
class MapboxSearchService {
  MapboxSearchService({String? token, http.Client? client})
      : _token = token ?? dotenv.env['MAPBOX_TOKEN'] ?? '',
        _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const String _base = 'https://api.mapbox.com/search/searchbox/v1';

  String? _sessionToken;
  String get _session => _sessionToken ??= _newSessionToken();

  /// Whether a Mapbox token is available; when false, calls short-circuit to
  /// empty/null results rather than hitting the network.
  bool get isConfigured => _token.isNotEmpty;

  /// Free-text POI/place search-as-you-type. [types] follows Search Box's own
  /// vocabulary (e.g. `'poi'`, or `'poi,address,place'`) — pass null for
  /// Mapbox's default mix. [proximityLat]/[proximityLng] bias results toward
  /// a location (e.g. the user's current position) without hard-filtering to
  /// it. Empty on no token, a too-short query, or any network/HTTP failure —
  /// never throws, so callers don't need their own try/catch.
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    int limit = 8,
    double? proximityLat,
    double? proximityLng,
    String? types,
  }) async {
    final q = query.trim();
    if (_token.isEmpty || q.length < 2) return const [];
    try {
      final uri = Uri.parse('$_base/suggest').replace(queryParameters: {
        'q': q,
        'access_token': _token,
        'session_token': _session,
        'limit': '$limit',
        if (types != null) 'types': types,
        if (proximityLat != null && proximityLng != null)
          'proximity': '$proximityLng,$proximityLat',
      });
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final suggestions = (data['suggestions'] as List?) ?? const [];
      return suggestions
          .map((s) {
            final m = s as Map<String, dynamic>;
            final categories = (m['poi_category'] as List?) ?? const [];
            return PlaceSuggestion(
              mapboxId: m['mapbox_id'] as String? ?? '',
              name: m['name'] as String? ?? '',
              placeFormatted: (m['place_formatted'] as String?) ??
                  (m['full_address'] as String?) ??
                  '',
              category: categories.isNotEmpty ? categories.first as String? : null,
            );
          })
          .where((s) => s.mapboxId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Resolves a suggestion's [mapboxId] (from [suggest]) into real
  /// coordinates, closing out the current billing session — the next
  /// [suggest] call starts a fresh one. Returns null on failure.
  Future<PlaceDetails?> retrieve(String mapboxId) async {
    if (_token.isEmpty || mapboxId.isEmpty) return null;
    final session = _session;
    _sessionToken = null; // session ends here regardless of outcome below
    try {
      final uri = Uri.parse('$_base/retrieve/$mapboxId').replace(queryParameters: {
        'access_token': _token,
        'session_token': session,
      });
      final res = await _client.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? const [];
      if (features.isEmpty) return null;
      final f = features.first as Map<String, dynamic>;
      final props = (f['properties'] as Map<String, dynamic>?) ?? const {};
      final geom = (f['geometry'] as Map<String, dynamic>?) ?? const {};
      final coords = (geom['coordinates'] as List?) ?? const [];
      if (coords.length < 2) return null;
      final categories = (props['poi_category'] as List?) ?? const [];
      return PlaceDetails(
        mapboxId: props['mapbox_id'] as String? ?? mapboxId,
        name: props['name'] as String? ?? '',
        placeFormatted:
            (props['place_formatted'] as String?) ?? (props['full_address'] as String?) ?? '',
        category: categories.isNotEmpty ? categories.first as String? : null,
        lng: (coords[0] as num).toDouble(),
        lat: (coords[1] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static final Random _rand = Random.secure();

  /// 16 random bytes as hex — a UUID-shaped value would also work, but
  /// Mapbox only requires an opaque unique string per session, and pulling in
  /// a `uuid` package for one random token isn't worth the dependency.
  String _newSessionToken() =>
      List<int>.generate(16, (_) => _rand.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
}

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A single geocoder result, decoupled from Mapbox's wire format so callers
/// never see raw JSON.
class GeoPlace {
  /// Short label, e.g. "San Francisco".
  final String name;

  /// Full formatted address / place name, e.g. "San Francisco, California".
  final String fullName;

  /// Mapbox `feature_type` (e.g. 'place', 'locality', 'region'). Drives result
  /// ranking so a precise city surfaces above a coarse region of the same name.
  final String featureType;
  final double? lat;
  final double? lng;

  /// Feature bounding box `[west, south, east, north]` (Mapbox v6 GeoJSON
  /// convention, W/S/E/N). Present for area features (place/region); null for
  /// point-like results (POI/address) that carry only a centre.
  final List<double>? bbox;

  const GeoPlace({
    required this.name,
    required this.fullName,
    this.featureType = '',
    this.lat,
    this.lng,
    this.bbox,
  });

  bool get hasCoords => lat != null && lng != null;
}

/// The single Mapbox-geocoding-aware class. Wraps the Mapbox Search Geocoding
/// **v6** endpoints — the legacy `geocoding/v5/mapbox.places` API is deprecated.
///
/// UI and state code call [search] / [reverse] instead of constructing Mapbox
/// URLs or parsing GeoJSON themselves, so the network detail lives in one place
/// and is easy to swap or mock in tests (inject an [http.Client]).
class GeocodingService {
  GeocodingService({String? token, http.Client? client})
      : _token = token ?? dotenv.env['MAPBOX_TOKEN'] ?? '',
        _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const String _base = 'https://api.mapbox.com/search/geocode/v6';

  /// Whether a Mapbox token is available; when false, calls short-circuit to
  /// empty results rather than hitting the network.
  bool get isConfigured => _token.isNotEmpty;

  /// Forward-geocode [query] into candidate places (cities, regions, …).
  /// Returns an empty list when unconfigured, the query is too short, or the
  /// request fails — never throws for ordinary network/HTTP errors.
  Future<List<GeoPlace>> search(
    String query, {
    int limit = 5,
    String types = 'place,locality,neighborhood,region',
  }) async {
    final q = query.trim();
    if (_token.isEmpty || q.length < 2) return const [];
    try {
      final uri = Uri.parse('$_base/forward').replace(queryParameters: {
        'q': q,
        'access_token': _token,
        'types': types,
        'limit': '$limit',
      });
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      // Prefer precise settlement types over a coarse region of the same name,
      // so tapping "Kyoto" flies to the city, not the prefecture. The index
      // tie-break keeps Mapbox's relevance order within each rank tier (Dart's
      // sort isn't guaranteed stable on its own).
      final places = _parse(res.body);
      final indexed = places.indexed.toList()
        ..sort((a, b) {
          final byRank =
              _typeRank(a.$2.featureType) - _typeRank(b.$2.featureType);
          return byRank != 0 ? byRank : a.$1 - b.$1;
        });
      return indexed.map((e) => e.$2).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Lower = more precise → ranks higher. Unknown/other types sit between
  /// settlements and regions so nothing is dropped, just reordered.
  static int _typeRank(String type) {
    switch (type) {
      case 'neighborhood':
      case 'locality':
      case 'place':
        return 0;
      case 'region':
      case 'country':
        return 2;
      default:
        return 1;
    }
  }

  /// Mapbox Static Images API URL for a small non-interactive map thumbnail
  /// (e.g. the Overview tab's trip hero card) — a plain image URL, not a
  /// live map widget, so it's cacheable through the same AppNetworkImage/
  /// cached_network_image path every other network image in the app already
  /// uses. Distinct from [search]/[reverse]: this doesn't hit the network
  /// itself, it just builds the URL a caller hands to an image widget. Style
  /// matches the Explore map's default (`outdoors-v12`, see
  /// explore_screen.dart's `_MapStyle.outdoors`) for visual consistency.
  /// Returns null when no token is configured, so callers can fall back to
  /// a placeholder rather than requesting a URL that will 401.
  ///
  /// [overlay] is a pre-built Mapbox overlay path segment (see
  /// [buildStaticMapOverlay]) — omit for a plain destination map. [autoFit]
  /// switches the position segment to `auto`, letting Mapbox frame the
  /// viewport to the overlay's markers/path instead of the explicit
  /// [lat]/[lng]/[zoom] — only meaningful when [overlay] is non-empty; there's
  /// nothing to fit to otherwise, so callers should leave it false when there
  /// are no stops to plot.
  static String? staticImageUrl({
    required double lat,
    required double lng,
    int zoom = 11,
    int width = 800,
    int height = 400,
    String styleId = 'outdoors-v12',
    String? overlay,
    bool autoFit = false,
  }) {
    final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
    if (token.isEmpty) return null;
    final overlaySegment = (overlay != null && overlay.isNotEmpty) ? '$overlay/' : '';
    final position = autoFit ? 'auto' : '$lng,$lat,$zoom';
    return 'https://api.mapbox.com/styles/v1/mapbox/$styleId/static/'
        '$overlaySegment$position/${width}x$height@2x?access_token=$token';
  }

  /// Builds the `{overlay}` segment [staticImageUrl] inserts before the
  /// position — comma-separated pin + path objects, per Mapbox's documented
  /// static-images overlay syntax. Pure string building, no network call.
  ///
  /// [pins]' `label` must be an integer 0–99 or a lowercase a–z (Mapbox's
  /// documented pin-label alphabet) — callers own picking a valid label,
  /// e.g. the Overview map card's day.stopIndex labels. Each pin and route
  /// carries its own `color` (6-digit hex, no '#' — see [hexFromArgb]) so a
  /// multi-day trip renders one distinct color per day; a single-day trip
  /// just passes the same color for everything. A route with fewer than 2
  /// points draws nothing, since a line needs at least two ends. The static
  /// API has no equivalent of the interactive map's direction arrows or day
  /// chips — this is the deliberately simplified thumbnail rendering.
  static String buildStaticMapOverlay({
    required List<({double lat, double lng, String label, String color})> pins,
    List<({List<({double lat, double lng})> points, String color})> routes = const [],
  }) {
    final parts = <String>[
      for (final p in pins) 'pin-s-${p.label}+${p.color}(${p.lng},${p.lat})',
      for (final r in routes)
        if (r.points.length >= 2)
          'path-3+${r.color}-0.85(${Uri.encodeComponent(_encodePolyline(r.points))})',
    ];
    return parts.join(',');
  }

  /// Converts an ARGB int (e.g. from lib/core/logic/trip_route.dart's
  /// tripDayColors) to the 6-digit, no-'#' hex string Mapbox's overlay
  /// syntax expects.
  static String hexFromArgb(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// Google Encoded Polyline Algorithm Format, precision 5 — the format
  /// Mapbox's `path-` overlay expects. No existing package in this repo did
  /// this; it's a well-known, short, pure algorithm, not worth a dependency
  /// for ~20 lines. https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static String _encodePolyline(List<({double lat, double lng})> points) {
    final buffer = StringBuffer();
    var prevLat = 0, prevLng = 0;
    for (final p in points) {
      final lat = (p.lat * 1e5).round();
      final lng = (p.lng * 1e5).round();
      _encodeSignedNumber(lat - prevLat, buffer);
      _encodeSignedNumber(lng - prevLng, buffer);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
  }

  static void _encodeSignedNumber(int num, StringBuffer buffer) {
    var sgnNum = num << 1;
    if (num < 0) sgnNum = ~sgnNum;
    while (sgnNum >= 0x20) {
      buffer.writeCharCode((0x20 | (sgnNum & 0x1f)) + 63);
      sgnNum >>= 5;
    }
    buffer.writeCharCode(sgnNum + 63);
  }

  /// Reverse-geocode a coordinate to its enclosing place. Returns null when
  /// unconfigured, no match exists, or the request fails.
  Future<GeoPlace?> reverse(
    double lat,
    double lng, {
    String types = 'place',
    int limit = 1,
  }) async {
    if (_token.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/reverse').replace(queryParameters: {
        'longitude': '$lng',
        'latitude': '$lat',
        'access_token': _token,
        'types': types,
        'limit': '$limit',
      });
      final res = await _client.get(uri);
      if (res.statusCode != 200) return null;
      final places = _parse(res.body);
      return places.isEmpty ? null : places.first;
    } catch (_) {
      return null;
    }
  }

  List<GeoPlace> _parse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final feats = (data['features'] as List?) ?? const [];
    return feats.map((f) {
      final m = f as Map<String, dynamic>;
      final props = (m['properties'] as Map<String, dynamic>?) ?? const {};
      final geom = (m['geometry'] as Map<String, dynamic>?) ?? const {};
      final coords = (geom['coordinates'] as List?) ?? const [];
      // v6 carries the bbox at the feature level; some payloads mirror it under
      // properties, so accept either. Coerce to exactly four finite doubles
      // (W/S/E/N) or treat as absent.
      final rawBbox = (m['bbox'] as List?) ?? (props['bbox'] as List?);
      final bbox = (rawBbox != null && rawBbox.length >= 4)
          ? [
              (rawBbox[0] as num).toDouble(),
              (rawBbox[1] as num).toDouble(),
              (rawBbox[2] as num).toDouble(),
              (rawBbox[3] as num).toDouble(),
            ]
          : null;
      return GeoPlace(
        name: (props['name'] as String?) ?? '',
        fullName: (props['full_address'] as String?) ??
            (props['place_formatted'] as String?) ??
            (props['name'] as String?) ??
            '',
        featureType: (props['feature_type'] as String?) ?? '',
        lng: coords.isNotEmpty ? (coords[0] as num?)?.toDouble() : null,
        lat: coords.length > 1 ? (coords[1] as num?)?.toDouble() : null,
        bbox: bbox,
      );
    }).toList();
  }
}

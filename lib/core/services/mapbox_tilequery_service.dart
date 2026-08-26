import 'dart:convert';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// One point of interest returned by a Tilequery lookup.
class NearbyPoi {
  final String name;
  final String? category;
  final double lat;
  final double lng;

  /// Straight-line distance from the query point, in meters, when Mapbox
  /// includes it (it does for point-geometry results, which POIs always are).
  final double? distanceMeters;

  /// Mapbox's own Maki icon identifier for this POI (e.g. `'town-hall'`,
  /// `'monument'`) — a symbol NAME for rendering a small map-pin glyph, not
  /// a photo (Tilequery has no photo field for any result; confirmed against
  /// the raw API response before building [iconForMaki]). Used to pick a
  /// more specific placeholder icon than a generic pin — see [iconForMaki].
  final String? maki;

  const NearbyPoi({
    required this.name,
    this.category,
    required this.lat,
    required this.lng,
    this.distanceMeters,
    this.maki,
  });

  /// Maps Mapbox's `maki` icon name to a Material icon, for a card
  /// placeholder that actually reflects the place's type — a government
  /// building looks different from a memorial or a park, even though none
  /// of them have a real photo. Falls back to a plain pin for anything not
  /// in this (necessarily partial — Maki has ~200 icons) list.
  static IconData iconForMaki(String? maki) {
    switch (maki) {
      case 'town-hall':
      case 'commercial':
      case 'bank':
        return Icons.account_balance;
      case 'monument':
      case 'memorial':
        return Icons.account_balance_outlined;
      case 'museum':
        return Icons.museum;
      case 'park':
      case 'garden':
      case 'park-alt1':
        return Icons.park;
      case 'zoo':
        return Icons.pets;
      case 'religious-christian':
        return Icons.church;
      case 'religious-muslim':
        return Icons.mosque;
      case 'religious-jewish':
        return Icons.synagogue;
      case 'religious-buddhist':
        return Icons.temple_buddhist;
      case 'religious-hindu':
        return Icons.temple_hindu;
      case 'restaurant':
      case 'fast-food':
        return Icons.restaurant;
      case 'cafe':
        return Icons.local_cafe;
      case 'bar':
      case 'beer':
        return Icons.local_bar;
      case 'lodging':
        return Icons.hotel;
      case 'shop':
      case 'shoe':
      case 'clothing-store':
      case 'grocery':
        return Icons.storefront;
      case 'hospital':
      case 'pharmacy':
        return Icons.local_hospital;
      case 'school':
      case 'college':
        return Icons.school;
      case 'parking':
      case 'parking-garage':
        return Icons.local_parking;
      case 'airport':
        return Icons.flight;
      case 'bus':
        return Icons.directions_bus;
      case 'rail':
      case 'rail-metro':
        return Icons.train;
      case 'mountain':
        return Icons.landscape;
      case 'beach':
        return Icons.beach_access;
      default:
        return Icons.place_outlined;
    }
  }
}

/// Wraps Mapbox's **Tilequery API** against the public
/// `mapbox.mapbox-streets-v8` tileset's `poi_label` layer — "what points of
/// interest exist near this coordinate," e.g. for a destination detail
/// page's "Nearby" section. Distinct from [MapboxSearchService] (free-text
/// search) and [GeocodingService] (address/city lookup) — this is a
/// proximity query with no text input at all. Reads a public,
/// Mapbox-hosted tileset, so the same MAPBOX_TOKEN already used everywhere
/// else in the app works with no additional scope.
class MapboxTilequeryService {
  MapboxTilequeryService({String? token, http.Client? client})
      : _token = token ?? dotenv.env['MAPBOX_TOKEN'] ?? '',
        _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const String _tileset = 'mapbox.mapbox-streets-v8';

  /// Whether a Mapbox token is available; when false, calls short-circuit to
  /// an empty list rather than hitting the network.
  bool get isConfigured => _token.isNotEmpty;

  /// Points of interest within [radiusMeters] of [lat]/[lng], nearest first.
  /// Empty on no token or any network/HTTP failure — never throws.
  Future<List<NearbyPoi>> nearby(
    double lat,
    double lng, {
    int radiusMeters = 500,
    int limit = 10,
  }) async {
    if (_token.isEmpty) return const [];
    try {
      final uri = Uri.parse(
        'https://api.mapbox.com/v4/$_tileset/tilequery/$lng,$lat.json',
      ).replace(queryParameters: {
        'radius': '$radiusMeters',
        'limit': '$limit',
        'layers': 'poi_label',
        'access_token': _token,
      });
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (data['features'] as List?) ?? const [];
      final pois = feats.map((f) {
        final m = f as Map<String, dynamic>;
        final props = (m['properties'] as Map<String, dynamic>?) ?? const {};
        final geom = (m['geometry'] as Map<String, dynamic>?) ?? const {};
        final coords = (geom['coordinates'] as List?) ?? const [];
        final tilequeryMeta = props['tilequery'] as Map<String, dynamic>?;
        // Tilequery's poi_label layer doesn't always carry a proper
        // `name` (confirmed against the raw response: plenty of real
        // features — parking lots, picnic tables, playgrounds — have
        // none), but it reliably carries `type`, a human-readable
        // category label ("Parking", "Picnic Table") — a far better
        // fallback than a hardcoded "Unnamed place" for the (fairly
        // common) unnamed case.
        final type = props['type'] as String?;
        final klass = props['class'] as String?;
        return NearbyPoi(
          name: (props['name'] as String?) ?? type ?? klass ?? 'Unnamed place',
          category: type ?? klass,
          lng: coords.isNotEmpty ? (coords[0] as num).toDouble() : lng,
          lat: coords.length > 1 ? (coords[1] as num).toDouble() : lat,
          distanceMeters: (tilequeryMeta?['distance'] as num?)?.toDouble(),
          maki: props['maki'] as String?,
        );
      }).toList()
        ..sort((a, b) => (a.distanceMeters ?? double.infinity)
            .compareTo(b.distanceMeters ?? double.infinity));
      return pois;
    } catch (_) {
      return const [];
    }
  }
}

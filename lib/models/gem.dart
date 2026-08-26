class Gem {
  final String id;
  final String gemName;
  final String? gemLocation;
  final String? category;
  final double? latitude;
  final double? longitude;
  final String? tagline;
  final String? description;
  final String? photoUrl;

  /// Full ordered photo set for the detail screen's gallery. Empty for every
  /// gem dropped before multi-photo support existed (and for every
  /// Mapbox-sourced place, which has no photos at all) — callers needing "all
  /// photos, however many there are" should use [allPhotos] rather than this
  /// directly.
  final List<String> photoUrls;
  final String? difficulty;
  final String? bestTimeToVisit;

  /// Estimated visit duration in minutes, for the Itinerary's spot meta line
  /// and day-summary planned-time rollup. Null means unknown/uncatalogued —
  /// excluded from time sums, never treated as zero. Backs
  /// `saved_gems.est_duration_min` (migration 20260806000600).
  final int? estDurationMin;

  final DateTime savedAt;
  final String? userId;

  /// Display name of the user who dropped this gem, from a `profiles`
  /// embed (LEFT join on `display_name`). Null when there is no matching
  /// profile or the join was omitted. Read-only — never written back.
  final String? dropperHandle;

  /// Mapbox's own Maki icon name (e.g. 'town-hall', 'parking') — set ONLY on
  /// a transient, in-memory Gem built from a [NearbyPoi] (see
  /// GemDetailScreen's poi-based constructor), never on a real saved_gems
  /// row and never persisted. Lets the detail screen's "no photo" fallback
  /// show the same specific icon the POI's own card already uses instead of
  /// the generic pin/food-etc. emoji.
  final String? maki;

  /// True only for a transient Gem built from a Mapbox POI rather than a
  /// real saved_gems row — there is no gem_saves row to create for it, so a
  /// bookmark tap can't attempt a real save (see GemDetailScreen).
  final bool isFromPoi;

  const Gem({
    required this.id,
    required this.gemName,
    this.gemLocation,
    this.category,
    this.latitude,
    this.longitude,
    this.tagline,
    this.description,
    this.photoUrl,
    this.photoUrls = const [],
    this.difficulty,
    this.bestTimeToVisit,
    this.estDurationMin,
    required this.savedAt,
    this.userId,
    this.dropperHandle,
    this.maki,
    this.isFromPoi = false,
  });

  factory Gem.fromJson(Map<String, dynamic> json) {
    double? lat, lng;
    final coords = json['gem_coords'];
    if (coords != null) {
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num?)?.toDouble();
        lat = (coords[1] as num?)?.toDouble();
      } else if (coords is Map) {
        lng = (coords['lng'] ?? coords['longitude'] as num?)?.toDouble();
        lat = (coords['lat'] ?? coords['latitude'] as num?)?.toDouble();
      }
    }
    // The profiles embed may arrive as a map (to-one), a list (to-many), or be
    // absent entirely if the join was dropped — tolerate all three.
    String? dropperHandle;
    final profiles = json['profiles'];
    if (profiles is Map) {
      dropperHandle = profiles['display_name'] as String?;
    } else if (profiles is List && profiles.isNotEmpty) {
      final first = profiles.first;
      if (first is Map) dropperHandle = first['display_name'] as String?;
    }
    return Gem(
      id: json['id'] as String,
      gemName: json['gem_name'] as String? ?? 'Unnamed Gem',
      gemLocation: json['gem_location'] as String?,
      category: json['category'] as String?,
      latitude: lat,
      longitude: lng,
      tagline: json['tagline'] as String?,
      description: json['description'] as String?,
      photoUrl: json['photo_url'] as String?,
      photoUrls: (json['photo_urls'] as List?)?.cast<String>() ?? const [],
      difficulty: json['difficulty'] as String?,
      bestTimeToVisit: json['best_time_to_visit'] as String?,
      estDurationMin: (json['est_duration_min'] as num?)?.toInt(),
      savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.now(),
      userId: json['user_id'] as String?,
      dropperHandle: dropperHandle,
    );
  }

  Map<String, dynamic> toInsert({
    required String userId,
    required double lat,
    required double lng,
  }) =>
      {
        'gem_name': gemName,
        'gem_location': gemLocation,
        'category': category,
        'gem_coords': {'lat': lat, 'lng': lng},
        'tagline': tagline,
        'description': description,
        'photo_url': photoUrl,
        'photo_urls': photoUrls,
        'difficulty': difficulty,
        'best_time_to_visit': bestTimeToVisit,
        'est_duration_min': estDurationMin,
        'user_id': userId,
      };

  static const Map<String, String> categoryEmoji = {
    'hiking': '🥾',
    'camping': '⛺',
    'viewpoint': '📸',
    'food': '🍜',
    'temple': '⛩️',
    'cave': '🗿',
    'coastal': '🌊',
    'nature': '🌿',
  };

  static const List<String> categories = [
    'hiking',
    'camping',
    'viewpoint',
    'food',
    'temple',
    'cave',
    'coastal',
    'nature',
  ];

  String get emoji => categoryEmoji[category] ?? '📍';
  String get displayCategory => category != null
      ? category![0].toUpperCase() + category!.substring(1)
      : 'Unknown';
  bool get hasCoords => latitude != null && longitude != null;

  /// Every photo for this gem, cover first. Falls back to [photoUrl] alone
  /// when [photoUrls] is empty (every gem dropped before multi-photo support,
  /// and every Mapbox-sourced place) — never both, since [photoUrls] already
  /// includes the cover when it's populated.
  List<String> get allPhotos =>
      photoUrls.isNotEmpty ? photoUrls : (photoUrl != null ? [photoUrl!] : []);
}

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
    this.difficulty,
    this.bestTimeToVisit,
    this.estDurationMin,
    required this.savedAt,
    this.userId,
    this.dropperHandle,
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
      difficulty: json['difficulty'] as String?,
      bestTimeToVisit: json['best_time_to_visit'] as String?,
      estDurationMin: (json['est_duration_min'] as num?)?.toInt(),
      savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ?? DateTime.now(),
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
    'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal', 'nature',
  ];

  String get emoji => categoryEmoji[category] ?? '📍';
  String get displayCategory => category != null
      ? category![0].toUpperCase() + category!.substring(1)
      : 'Unknown';
  bool get hasCoords => latitude != null && longitude != null;
}

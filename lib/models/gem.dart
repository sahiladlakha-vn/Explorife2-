class Gem {
  final String id;
  final String gemName;
  final String? gemLocation;
  final String? category;
  final double? latitude;
  final double? longitude;
  final String? description;
  final String? photoUrl;
  final String? difficulty;
  final String? bestTimeToVisit;
  final DateTime savedAt;
  final String? userId;

  const Gem({
    required this.id,
    required this.gemName,
    this.gemLocation,
    this.category,
    this.latitude,
    this.longitude,
    this.description,
    this.photoUrl,
    this.difficulty,
    this.bestTimeToVisit,
    required this.savedAt,
    this.userId,
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
    return Gem(
      id: json['id'] as String,
      gemName: json['gem_name'] as String? ?? 'Unnamed Gem',
      gemLocation: json['gem_location'] as String?,
      category: json['category'] as String?,
      latitude: lat,
      longitude: lng,
      description: json['description'] as String?,
      photoUrl: json['photo_url'] as String?,
      difficulty: json['difficulty'] as String?,
      bestTimeToVisit: json['best_time_to_visit'] as String?,
      savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ?? DateTime.now(),
      userId: json['user_id'] as String?,
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
        'description': description,
        'photo_url': photoUrl,
        'difficulty': difficulty,
        'best_time_to_visit': bestTimeToVisit,
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

class HikeTrack {
  final String id;
  final String userId;
  final String title;
  final String activityType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? distanceKm;
  final int? durationSeconds;
  final double? elevationGainM;
  final bool featured;
  final DateTime createdAt;

  const HikeTrack({
    required this.id,
    required this.userId,
    required this.title,
    required this.activityType,
    required this.startedAt,
    this.endedAt,
    this.distanceKm,
    this.durationSeconds,
    this.elevationGainM,
    required this.featured,
    required this.createdAt,
  });

  factory HikeTrack.fromJson(Map<String, dynamic> json) => HikeTrack(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String? ?? 'Untitled Hike',
        activityType: json['activity_type'] as String? ?? 'hiking',
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ?? DateTime.now(),
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        durationSeconds: json['duration_seconds'] as int?,
        elevationGainM: (json['elevation_gain_m'] as num?)?.toDouble(),
        featured: json['featured'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get durationFormatted {
    if (durationSeconds == null) return '—';
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static const Map<String, String> activityEmoji = {
    'hiking': '🥾',
    'trail_running': '🏃',
    'cycling': '🚴',
    'climbing': '⛰️',
    'kayaking': '🚣',
    'skiing': '⛷️',
  };

  String get emoji => activityEmoji[activityType] ?? '🏕️';
}

class SplitGroup {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final DateTime createdAt;

  const SplitGroup({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
  });

  factory SplitGroup.fromJson(Map<String, dynamic> json) => SplitGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Trip',
        description: json['description'] as String?,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class SplitExpense {
  final String id;
  final String groupId;
  final String paidBy;
  final String description;
  final double amount;
  final String currency;
  final DateTime createdAt;

  const SplitExpense({
    required this.id,
    required this.groupId,
    required this.paidBy,
    required this.description,
    required this.amount,
    required this.currency,
    required this.createdAt,
  });

  factory SplitExpense.fromJson(Map<String, dynamic> json) => SplitExpense(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        paidBy: json['paid_by'] as String,
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? 'USD',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

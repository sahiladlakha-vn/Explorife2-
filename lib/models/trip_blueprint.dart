/// A curated, read-only itinerary template. Backs `public.trip_blueprints`.
/// Selecting one in Setup Step 2 seeds a fresh trip's stops from [items].
///
/// Read-only from the app's perspective — no `copyWith`, no `toJson`. An in-app
/// blueprint editor would be its own feature with its own model.
class TripBlueprint {
  final String id;

  /// Indexed by place name ('Hoi An', 'Tokyo'), not a foreign key — there's no
  /// destinations table yet. Becomes a soft reference if/when one exists.
  final String location;

  final String title;

  /// Editorial copy shown verbatim in the Step 2 row
  /// (e.g. 'Slow culture · 4.8★ · 2,340 saves'). Curated server-side — star
  /// ratings / save counts are deliberately NOT modelled as live fields.
  final String? meta;

  /// Decoded `items_json`. Parsing lives here so `TripProvider.seedFromBlueprint`
  /// can iterate ready-made items rather than carrying decode logic.
  final List<BlueprintItem> items;

  final int saveCount;
  final DateTime createdAt;

  const TripBlueprint({
    required this.id,
    required this.location,
    required this.title,
    this.meta,
    this.items = const [],
    this.saveCount = 0,
    required this.createdAt,
  });

  /// Highest day index in the template — lets the row show "6 days" without a
  /// dedicated column. 0 for an empty blueprint.
  int get nights {
    if (items.isEmpty) return 0;
    return items.map((i) => i.day).reduce((a, b) => a > b ? a : b);
  }

  /// Total planned stops, for copy like "12 stops planned".
  int get itemCount => items.length;

  factory TripBlueprint.fromJson(Map<String, dynamic> j) {
    // A malformed row may have null items_json — default to empty, never throw.
    final raw = j['items_json'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((m) => BlueprintItem.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <BlueprintItem>[];
    return TripBlueprint(
      id: j['id'] as String,
      location: j['location'] as String,
      title: j['title'] as String,
      meta: j['meta'] as String?,
      items: items,
      saveCount: (j['save_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}

/// One templated stop inside a [TripBlueprint]. Mirrors the seedable shape of
/// [TripStop] (minus the trip-scoped id/tripId). Private detail of the
/// blueprint, not a standalone concept.
class BlueprintItem {
  final int day;
  final String slot;
  final String? gemId;
  final Map<String, dynamic>? customPayload;
  final int priceVnd;
  final int sortOrder;

  const BlueprintItem({
    required this.day,
    required this.slot,
    this.gemId,
    this.customPayload,
    this.priceVnd = 0,
    this.sortOrder = 0,
  });

  factory BlueprintItem.fromJson(Map<String, dynamic> j) {
    final payload = j['custom_payload'];
    return BlueprintItem(
      day: (j['day'] as num).toInt(),
      slot: j['slot'] as String,
      gemId: j['gem_id'] as String?,
      customPayload:
          payload is Map ? Map<String, dynamic>.from(payload) : null,
      priceVnd: (j['price_vnd'] as num?)?.toInt() ?? 0,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

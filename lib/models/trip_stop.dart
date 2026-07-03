/// A single item placed in a trip's itinerary — one [slot] of one [day].
///
/// Backs `public.trip_stops`. A stop is either a saved gem ([gemId] set) or a
/// freeform custom entry ([customPayload] holds its title/note). Plain Dart,
/// no codegen — mirrors the [Gem]/[Trip] convention.
class TripStop {
  final String id;
  final String tripId;
  final int day;

  /// One of 'morning' | 'afternoon' | 'evening'. Kept as a String to match the
  /// DB check constraint and the `TripProvider.addStop({required String slot})`
  /// signature — no slot enum to keep that contract friction-free.
  final String slot;

  /// References `saved_gems.id` when this stop is a gem; null for custom stops.
  final String? gemId;

  /// Freeform stop data (e.g. {'title': …, 'note': …}) when [gemId] is null.
  final Map<String, dynamic>? customPayload;

  final int priceVnd;
  final int sortOrder;

  const TripStop({
    required this.id,
    required this.tripId,
    required this.day,
    required this.slot,
    this.gemId,
    this.customPayload,
    this.priceVnd = 0,
    this.sortOrder = 0,
  });

  /// True when this is a freeform stop rather than a saved gem.
  bool get isCustom => gemId == null;

  /// Display title for custom stops; null for gem stops (look up the gem).
  String? get customTitle => customPayload?['title'] as String?;

  factory TripStop.fromJson(Map<String, dynamic> j) {
    final payload = j['custom_payload'];
    return TripStop(
      id: j['id'] as String,
      tripId: j['trip_id'] as String,
      day: (j['day'] as num).toInt(),
      slot: j['slot'] as String,
      gemId: j['gem_id'] as String?,
      customPayload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : null,
      priceVnd: (j['price_vnd'] as num?)?.toInt() ?? 0,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'day': day,
        'slot': slot,
        'gem_id': gemId,
        'custom_payload': customPayload,
        'price_vnd': priceVnd,
        'sort_order': sortOrder,
      };

  TripStop copyWith({int? priceVnd, int? sortOrder, int? day, String? slot}) =>
      TripStop(
        id: id,
        tripId: tripId,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        gemId: gemId,
        customPayload: customPayload,
        priceVnd: priceVnd ?? this.priceVnd,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

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

  // ── Transit-in leg ────────────────────────────────────────────────────────
  // How you get FROM the previous stop TO this one. All four are nullable and
  // move together: a stop with no transit leg (the day's first stop, or a
  // walk-up) leaves them null. Back `trip_stops.transit_*` (migration
  // 20260713000100). transitCostVnd stays in the VND trip-money world.

  /// e.g. 'walk' | 'taxi' | 'bus' | 'train' | 'ferry'. Freeform to match the
  /// nullable text column — no CHECK constraint, so no enum.
  final String? transitMode;

  /// Route/line label, e.g. 'Line 1' or 'Grab'. Null when not applicable.
  final String? transitLine;

  final int? transitDurationMin;

  /// Cost of the transit leg in VND. See the null/0 distinction on [hasTransit].
  final int? transitCostVnd;

  const TripStop({
    required this.id,
    required this.tripId,
    required this.day,
    required this.slot,
    this.gemId,
    this.customPayload,
    this.priceVnd = 0,
    this.sortOrder = 0,
    this.transitMode,
    this.transitLine,
    this.transitDurationMin,
    this.transitCostVnd,
  });

  /// True when this is a freeform stop rather than a saved gem.
  bool get isCustom => gemId == null;

  /// True when this stop has a transit-in leg to render. [transitMode] is the
  /// anchor: a leg without a mode isn't a leg. (A leg may still have a null
  /// [transitCostVnd] — cost unknown — which is why we don't gate on cost.)
  bool get hasTransit => transitMode != null;

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
      transitMode: j['transit_mode'] as String?,
      transitLine: j['transit_line'] as String?,
      transitDurationMin: (j['transit_duration_min'] as num?)?.toInt(),
      transitCostVnd: (j['transit_cost_vnd'] as num?)?.toInt(),
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
        'transit_mode': transitMode,
        'transit_line': transitLine,
        'transit_duration_min': transitDurationMin,
        'transit_cost_vnd': transitCostVnd,
      };

  // Sentinel so copyWith can distinguish "not provided" from "set to null" for
  // the four transit fields — "remove transit from this stop" is a real edit
  // path, and the plain `?? this.x` pattern can't clear a value to null. Pass
  // `transitMode: null` (etc.) to clear; omit to preserve.
  //
  // KNOWN LIMITATION (pre-existing, intentionally not touched this pass):
  // [gemId] and [customPayload] are carried over verbatim and aren't even
  // copyWith params, so they can't be changed or cleared here despite gem_id
  // being ON DELETE SET NULL. Left as-is to keep this change scoped to transit;
  // worth a sentinel pass of its own if a gem-clear edit path appears.
  static const Object _unset = Object();

  TripStop copyWith({
    int? priceVnd,
    int? sortOrder,
    int? day,
    String? slot,
    Object? transitMode = _unset,
    Object? transitLine = _unset,
    Object? transitDurationMin = _unset,
    Object? transitCostVnd = _unset,
  }) =>
      TripStop(
        id: id,
        tripId: tripId,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        gemId: gemId,
        customPayload: customPayload,
        priceVnd: priceVnd ?? this.priceVnd,
        sortOrder: sortOrder ?? this.sortOrder,
        transitMode: identical(transitMode, _unset)
            ? this.transitMode
            : transitMode as String?,
        transitLine: identical(transitLine, _unset)
            ? this.transitLine
            : transitLine as String?,
        transitDurationMin: identical(transitDurationMin, _unset)
            ? this.transitDurationMin
            : transitDurationMin as int?,
        transitCostVnd: identical(transitCostVnd, _unset)
            ? this.transitCostVnd
            : transitCostVnd as int?,
      );
}

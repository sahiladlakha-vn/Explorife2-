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

  /// Freeform stop data (e.g. {'title': …}) when [gemId] is null. When the
  /// stop was picked from a real Mapbox place (AddStopSheet's nearby/search
  /// results) rather than typed as a pure freeform name, it also carries
  /// `lat`/`lng` — the only thing that makes a custom stop plottable on the
  /// trip map (see trip_route.dart's `_syntheticPlottableGem`). A stop with
  /// just a title and no lat/lng simply doesn't appear on the map, same as
  /// it always has.
  final Map<String, dynamic>? customPayload;

  /// VND cost of this stop. MONEY CONTRACT (matches trip_bookings.amountVnd
  /// exactly, see that model's doc comment): null = TBD, not yet priced;
  /// 0 = confirmed free. Never coalesce null to 0 — sum it under the
  /// null-excluded/0-counted rule, same as every other *_vnd field in this
  /// app's rollups. Nullable as of migration 20260806000800; existing rows
  /// created before that migration were NOT backfilled to null, so a stop's
  /// price_vnd = 0 today may honestly be either "confirmed free" (post-
  /// migration) or "never priced" (pre-migration, ambiguous — see that
  /// migration's own comment).
  final int? priceVnd;
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

  /// Plain 'HH:mm' time-of-day, purely informational/editable — display
  /// order is still [sortOrder], not derived from this. Null means no time
  /// was set. Back `trip_stops.start_time` (migration 20260718000000).
  final String? startTime;

  /// Freeform per-stop notes, same migration as [startTime]. Distinct from
  /// [customTitle] (which lives in [customPayload] and only applies to
  /// custom stops) — notes apply to any stop, gem-backed or custom.
  final String? notes;

  const TripStop({
    required this.id,
    required this.tripId,
    required this.day,
    required this.slot,
    this.gemId,
    this.customPayload,
    this.priceVnd,
    this.sortOrder = 0,
    this.transitMode,
    this.transitLine,
    this.transitDurationMin,
    this.transitCostVnd,
    this.startTime,
    this.notes,
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
      priceVnd: (j['price_vnd'] as num?)?.toInt(),
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      transitMode: j['transit_mode'] as String?,
      transitLine: j['transit_line'] as String?,
      transitDurationMin: (j['transit_duration_min'] as num?)?.toInt(),
      transitCostVnd: (j['transit_cost_vnd'] as num?)?.toInt(),
      // Postgres `time` round-trips as an 'HH:mm:ss' string; trim to 'HH:mm'
      // to match what the editor writes and displays.
      startTime: (j['start_time'] as String?)?.substring(0, 5),
      notes: j['notes'] as String?,
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
        'start_time': startTime,
        'notes': notes,
      };

  // Sentinel so copyWith can distinguish "not provided" from "set to null" for
  // the nullable fields below — "clear this value" is a real edit path, and
  // the plain `?? this.x` pattern can't clear a value to null. Pass
  // `transitMode: null` (etc.) to clear; omit to preserve.
  //
  // KNOWN LIMITATION (pre-existing, intentionally not touched this pass):
  // [gemId] is still carried over verbatim and isn't a copyWith param, so it
  // can't be changed/cleared here despite gem_id being ON DELETE SET NULL.
  // [customPayload] *is* now a param (needed for inline title editing) —
  // only that one gap is closed this pass.
  static const Object _unset = Object();

  TripStop copyWith({
    Object? priceVnd = _unset,
    int? sortOrder,
    int? day,
    String? slot,
    Object? transitMode = _unset,
    Object? transitLine = _unset,
    Object? transitDurationMin = _unset,
    Object? transitCostVnd = _unset,
    Object? customPayload = _unset,
    Object? startTime = _unset,
    Object? notes = _unset,
  }) =>
      TripStop(
        id: id,
        tripId: tripId,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        gemId: gemId,
        customPayload: identical(customPayload, _unset)
            ? this.customPayload
            : customPayload as Map<String, dynamic>?,
        priceVnd:
            identical(priceVnd, _unset) ? this.priceVnd : priceVnd as int?,
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
        startTime: identical(startTime, _unset)
            ? this.startTime
            : startTime as String?,
        notes: identical(notes, _unset) ? this.notes : notes as String?,
      );
}

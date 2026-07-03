import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';
import '../models/trip_stop.dart';
import '../models/trip_blueprint.dart';
import '../models/trip_vibe.dart';

/// Slot ordering for itinerary reads. Module-level const, used by stopsForDay.
const Map<String, int> _slotOrder = {'morning': 0, 'afternoon': 1, 'evening': 2};

/// Owns trips, their stops, and the blueprint catalogue. Pure reads recompute
/// on each call (the lists are tiny; cache invalidation is the bigger risk).
/// Mutators are optimistic with rollback, except [createTrip]/[seedFromBlueprint]
/// which block navigation and so await-then-commit.
///
/// Decoupled from GemProvider: budget bucketing needs a gem's raw category, so
/// the app injects a lookup callback rather than importing GemProvider here.
class TripProvider extends ChangeNotifier {
  TripProvider({
    required SupabaseClient supabase,
    required String userId,
    required String? Function(String gemId) gemCategoryLookup,
  })  : _supabase = supabase,
        _currentUserId = userId,
        _gemCategoryLookup = gemCategoryLookup;

  final SupabaseClient _supabase;
  final String _currentUserId;
  final String? Function(String gemId) _gemCategoryLookup;

  // --- State: keyed caches + status channel. No computed values cached. ---
  final Map<String, Trip> _trips = {}; // by trip id
  final Map<String, List<TripStop>> _stopsByTrip = {}; // by trip id
  final List<TripBlueprint> _blueprints = []; // small; filter on read
  bool _isLoading = false;
  String? _lastError;

  // --- Status getters ---
  bool get isLoading => _isLoading;
  String? get error => _lastError;

  /// The owner id this instance queries under. Exposed so the proxy provider in
  /// main.dart can detect an auth change and rebuild (Option A: a userId change
  /// yields a fresh provider rather than mutating this final field).
  String get userId => _currentUserId;

  // --- Pure reads (safe in build()) ---

  /// All cached trips, soonest start first.
  List<Trip> get trips {
    final list = _trips.values.toList();
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  /// The soonest trip that starts within the next 30 days, or null.
  Trip? get activeTrip {
    for (final t in trips) {
      if (t.isUpcoming) return t;
    }
    return null;
  }

  Trip? tripById(String id) => _trips[id];

  int tripsCountFor(String userId) =>
      _trips.values.where((t) => t.ownerId == userId).length;

  List<TripBlueprint> get blueprints => List.unmodifiable(_blueprints);

  List<TripBlueprint> blueprintsFor(String location) {
    final q = location.toLowerCase();
    return _blueprints
        .where((b) => b.location.toLowerCase() == q)
        .toList();
  }

  /// Stops for one day, ordered slot-first then by sortOrder.
  List<TripStop> stopsForDay(String tripId, int day) {
    final list =
        (_stopsByTrip[tripId] ?? const <TripStop>[]).where((s) => s.day == day).toList();
    list.sort((a, b) {
      final s = _slotOrder[a.slot]!.compareTo(_slotOrder[b.slot]!);
      return s != 0 ? s : a.sortOrder.compareTo(b.sortOrder);
    });
    return list;
  }

  int dayTotal(String tripId, int day) =>
      stopsForDay(tripId, day).fold(0, (sum, s) => sum + s.priceVnd);

  int totalSpent(String tripId) =>
      (_stopsByTrip[tripId] ?? const <TripStop>[]).fold(0, (sum, s) => sum + s.priceVnd);

  /// Spend per budget bucket. Always returns all four keys (zero-filled) so the
  /// chart can render a stable set of bars.
  Map<String, int> categoryTotals(String tripId) {
    final totals = <String, int>{
      'stay': 0,
      'food': 0,
      'activity': 0,
      'transit': 0,
    };
    for (final s in _stopsByTrip[tripId] ?? const <TripStop>[]) {
      final bucket = _categoryFor(s);
      totals[bucket] = (totals[bucket] ?? 0) + s.priceVnd;
    }
    return totals;
  }

  // --- Lifecycle ---

  /// One-shot load. Never rethrows — failures surface via [error] so the UI can
  /// render an empty/retry state instead of crashing.
  Future<void> init() async {
    // No signed-in user yet (auth still resolving, or signed out): don't fire
    // `owner_id=eq.` with an empty string — `owner_id` is a uuid column, so an
    // empty filter value 400s (22P02) instead of returning an empty set. Leave
    // the caches empty; the proxy rebuilds this provider once auth resolves.
    if (_currentUserId.isEmpty) return;
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    // TODO(realtime): subscribe to trip_stops changes here once collab ships.
    try {
      final tripRows = await _supabase
          .from('trips')
          .select()
          .eq('owner_id', _currentUserId);
      _trips.clear();
      _stopsByTrip.clear();
      for (final r in tripRows) {
        final t = Trip.fromJson(r);
        _trips[t.id] = t;
        _stopsByTrip[t.id] = [];
      }

      final tripIds = _trips.keys.toList();
      if (tripIds.isNotEmpty) {
        final stopRows = await _supabase
            .from('trip_stops')
            .select()
            .inFilter('trip_id', tripIds);
        for (final r in stopRows) {
          final s = TripStop.fromJson(r);
          (_stopsByTrip[s.tripId] ??= []).add(s);
        }
      }

      final bpRows = await _supabase.from('trip_blueprints').select();
      _blueprints
        ..clear()
        ..addAll(bpRows.map((r) => TripBlueprint.fromJson(r)));
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Mutators ---

  /// Creates the trip and, if `draft.templateChoice == 'blueprint' &&
  /// draft.blueprintId != null`, seeds stops from that blueprint atomically.
  /// Callers must NOT call [seedFromBlueprint] separately.
  ///
  /// Blocks navigation (caller routes to the returned id), so this awaits the
  /// insert then commits — no optimistic state to show. Rethrows on failure.
  Future<Trip> createTrip(TripDraft draft) async {
    final row = await _supabase
        .from('trips')
        .insert({
          'owner_id': _currentUserId,
          // Empty name is valid (column is NOT NULL, not non-empty); Trip
          // .displayName supplies the "<location> escape" fallback in the UI.
          'name': '',
          'location': draft.location ?? '',
          'start_date':
              (draft.dateStart ?? DateTime.now()).toIso8601String().substring(0, 10),
          'end_date':
              (draft.dateEnd ?? DateTime.now()).toIso8601String().substring(0, 10),
          'budget_vnd': draft.budgetVnd,
          'currency': 'VND',
          'vibe': draft.vibe?.key,
          'template_id':
              draft.templateChoice == 'blueprint' ? draft.blueprintId : null,
        })
        .select()
        .single();

    final trip = Trip.fromJson(row);
    _trips[trip.id] = trip;
    _stopsByTrip[trip.id] = [];

    if (draft.templateChoice == 'blueprint' && draft.blueprintId != null) {
      await seedFromBlueprint(trip.id, draft.blueprintId!);
    }
    notifyListeners();
    return trip;
  }

  /// Awaited before the builder is shown, so non-optimistic: insert the seeded
  /// rows, populate the cache, notify once. Rethrows on failure.
  Future<void> seedFromBlueprint(String tripId, String blueprintId) async {
    final bp = _blueprints.firstWhere(
      (b) => b.id == blueprintId,
      orElse: () => throw StateError('Blueprint $blueprintId not found'),
    );
    if (bp.items.isEmpty) {
      _stopsByTrip[tripId] = [];
      notifyListeners();
      return;
    }

    final payload = bp.items
        .map((i) => {
              'trip_id': tripId,
              'day': i.day,
              'slot': i.slot,
              'gem_id': i.gemId,
              'custom_payload': i.customPayload,
              'price_vnd': i.priceVnd,
              'sort_order': i.sortOrder,
            })
        .toList();

    final rows =
        await _supabase.from('trip_stops').insert(payload).select();
    _stopsByTrip[tripId] =
        rows.map((r) => TripStop.fromJson(r)).toList();
    notifyListeners();
  }

  Future<TripStop> addStop({
    required String tripId,
    required int day,
    required String slot,
    String? gemId,
    Map<String, dynamic>? customPayload,
    required int priceVnd,
  }) async {
    // Append after existing stops in the same day+slot for a stable order.
    final sortOrder = (_stopsByTrip[tripId] ?? const <TripStop>[])
        .where((s) => s.day == day && s.slot == slot)
        .length;

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = TripStop(
      id: tempId,
      tripId: tripId,
      day: day,
      slot: slot,
      gemId: gemId,
      customPayload: customPayload,
      priceVnd: priceVnd,
      sortOrder: sortOrder,
    );
    _stopsByTrip[tripId] = [...?_stopsByTrip[tripId], optimistic];
    notifyListeners();

    // TODO(races): last-write-wins is fine for v1 (likely racer is the same
    // user double-tapping); revisit when realtime/collab lands.
    try {
      final row = await _supabase
          .from('trip_stops')
          .insert({
            'trip_id': tripId,
            'day': day,
            'slot': slot,
            'gem_id': gemId,
            'custom_payload': customPayload,
            'price_vnd': priceVnd,
            'sort_order': sortOrder,
          })
          .select()
          .single();
      final saved = TripStop.fromJson(row);
      _stopsByTrip[tripId] = _stopsByTrip[tripId]!
          .map((s) => s.id == tempId ? saved : s)
          .toList();
      notifyListeners();
      return saved;
    } catch (e) {
      _stopsByTrip[tripId] =
          _stopsByTrip[tripId]!.where((s) => s.id != tempId).toList();
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateStopPrice(String stopId, int newPriceVnd) async {
    final loc = _locate(stopId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _stopsByTrip[tripId]![index];

    _stopsByTrip[tripId]![index] = old.copyWith(priceVnd: newPriceVnd);
    notifyListeners();

    // TODO(races): last-write-wins; see addStop.
    try {
      await _supabase
          .from('trip_stops')
          .update({'price_vnd': newPriceVnd}).eq('id', stopId);
    } catch (e) {
      _stopsByTrip[tripId]![index] = old; // rollback
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeStop(String stopId) async {
    final loc = _locate(stopId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final removed = _stopsByTrip[tripId]![index];

    _stopsByTrip[tripId]!.removeAt(index);
    notifyListeners();

    try {
      await _supabase.from('trip_stops').delete().eq('id', stopId);
    } catch (e) {
      _stopsByTrip[tripId]!.insert(index, removed); // rollback to position
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Writes a collaborator permission. NOTE: blocked by RLS until the share
  /// step adds a `security definer is_trip_owner()` helper (see migration flag).
  Future<void> setPermission(
      String tripId, String userId, String permission) async {
    // TODO(collab): wire trip_collaborators reads + RLS write policy here.
    await _supabase.from('trip_collaborators').upsert({
      'trip_id': tripId,
      'user_id': userId,
      'permission': permission,
    });
    notifyListeners();
  }

  // --- Internal helpers ---

  /// Finds (tripId, index) for a stop across the cache, or null if absent.
  (String, int)? _locate(String stopId) {
    for (final entry in _stopsByTrip.entries) {
      final i = entry.value.indexWhere((s) => s.id == stopId);
      if (i != -1) return (entry.key, i);
    }
    return null;
  }

  String _categoryFor(TripStop s) {
    if (s.gemId != null) return _mapToBucket(_gemCategoryLookup(s.gemId!));
    return _mapToBucket(s.customPayload?['type'] as String?);
  }

  /// Collapses a raw gem category (or custom 'type') into one of the four
  /// budget buckets. The bucket names contain themselves, so custom payloads
  /// that already use 'stay'/'food'/'transit'/'activity' pass through unchanged.
  String _mapToBucket(String? raw) {
    if (raw == null) return 'activity';
    final r = raw.toLowerCase();
    if (r.contains('food') ||
        r.contains('restaurant') ||
        r.contains('cafe') ||
        r.contains('bar')) {
      return 'food';
    }
    if (r.contains('stay') ||
        r.contains('hotel') ||
        r.contains('hostel') ||
        r.contains('resort') ||
        r.contains('homestay')) {
      return 'stay';
    }
    if (r.contains('transit') ||
        r.contains('flight') ||
        r.contains('taxi') ||
        r.contains('transport')) {
      return 'transit';
    }
    return 'activity';
  }
}

/// Transient builder for Setup Steps 1–2. Not persisted; consumed by createTrip.
class TripDraft {
  String? location;
  DateTime? dateStart;
  DateTime? dateEnd;
  int budgetVnd = 0;
  TripVibe? vibe;
  String templateChoice = 'fresh'; // 'fresh' | 'blueprint'
  String? blueprintId;
}

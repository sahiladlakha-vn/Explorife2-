import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';
import '../models/trip_stop.dart';
import '../models/trip_blueprint.dart';
import '../models/trip_checklist_item.dart';
import '../models/trip_checklist_template.dart';
import '../models/trip_budget_template.dart';
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
  final Map<String, List<TripChecklistItem>> _checklistByTrip = {}; // by trip id
  final Map<String, Map<String, int>> _plannedByTrip =
      {}; // trip id -> {category: planned vnd}
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

  /// All cached stops for a trip, in cache order (unsorted). Mirrors
  /// [BookingProvider.bookingsFor] — a pure read safe to call in build().
  /// Returns a const empty list for an unknown/unfetched trip (never null).
  /// Callers that need ordering use [stopsForDay]; the insights layer only
  /// needs the flat set (it buckets and dedups, order-independent).
  List<TripStop> stopsFor(String tripId) =>
      _stopsByTrip[tripId] ?? const <TripStop>[];

  /// Public bucketer for one stop — the same category collapse the budget
  /// chart uses ([_categoryFor] → [_mapToBucket]). Exposed so the insights
  /// layer ([actualSpendByCategory]) can bucket stops without importing
  /// GemProvider or reimplementing the mapping.
  String bucketForStop(TripStop s) => _categoryFor(s);

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

  /// Planned spend per budget bucket — the "planned" line for the Summary
  /// Planned-vs-Actual chart. Always returns all four keys (zero-filled) so the
  /// chart pairs cleanly with [categoryTotals].
  ///
  /// Prefers the seeded/customized rows in [_plannedByTrip]; falls back to a
  /// freshly-computed vibe default for trips with no budget rows yet (legacy
  /// trips created before this feature, or before the seed lands). The fallback
  /// is NOT persisted here — it's a read-time default only.
  Map<String, int> plannedByCategory(String tripId) {
    final cached = _plannedByTrip[tripId];
    if (cached != null && cached.isNotEmpty) {
      return {for (final c in budgetCategories) c: cached[c] ?? 0};
    }
    final trip = _trips[tripId];
    if (trip == null) return {for (final c in budgetCategories) c: 0};
    return plannedBudgetFor(trip.vibe, trip.budgetVnd);
  }

  /// Sets the planned amount for one bucket. Optimistic upsert with rollback,
  /// mirroring [toggleChecklistItem]. Reserved for the deferred editing UI — no
  /// caller today, but the write path is here so the seed isn't the only way a
  /// row is ever created.
  Future<void> updatePlannedForCategory(
      String tripId, String category, int plannedVnd) async {
    final before = _plannedByTrip[tripId] == null
        ? null
        : Map<String, int>.from(_plannedByTrip[tripId]!);

    (_plannedByTrip[tripId] ??= {})[category] = plannedVnd; // optimistic
    notifyListeners();

    try {
      await _supabase.from('trip_category_budgets').upsert(
        {'trip_id': tripId, 'category': category, 'planned_vnd': plannedVnd},
        onConflict: 'trip_id,category',
      );
    } catch (e) {
      if (before == null) {
        _plannedByTrip.remove(tripId);
      } else {
        _plannedByTrip[tripId] = before; // rollback by snapshot
      }
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Checklist items for a trip, sorted by section render order then sortOrder.
  /// Returns an unmodifiable view: callers (Summary screen) render it directly
  /// and must route mutations through [toggleChecklistItem], never the list.
  List<TripChecklistItem> checklistFor(String tripId) {
    final list = List<TripChecklistItem>.from(
        _checklistByTrip[tripId] ?? const <TripChecklistItem>[]);
    list.sort((a, b) {
      final s = TripChecklistItem.sectionOrder
          .indexOf(a.section)
          .compareTo(TripChecklistItem.sectionOrder.indexOf(b.section));
      return s != 0 ? s : a.sortOrder.compareTo(b.sortOrder);
    });
    return List.unmodifiable(list);
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
      _checklistByTrip.clear();
      _plannedByTrip.clear();
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

        final checklistRows = await _supabase
            .from('trip_checklist_items')
            .select()
            .inFilter('trip_id', tripIds);
        for (final r in checklistRows) {
          final c = TripChecklistItem.fromJson(r);
          (_checklistByTrip[c.tripId] ??= []).add(c);
        }

        final budgetRows = await _supabase
            .from('trip_category_budgets')
            .select()
            .inFilter('trip_id', tripIds);
        for (final r in budgetRows) {
          final tripId = r['trip_id'] as String;
          final category = r['category'] as String;
          (_plannedByTrip[tripId] ??= {})[category] =
              (r['planned_vnd'] as num).toInt();
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
  ///
  /// After the trip (and any blueprint stops) commit, it seeds the pre-trip
  /// checklist. That seed is NON-fatal: the trip row already exists, so a
  /// checklist failure is logged to [error] and swallowed rather than rethrown —
  /// createTrip only rethrows for failures that mean "no trip was created".
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

    // Non-fatal: the trip is already committed. seedChecklistForTrip rethrows on
    // a genuine seed (insert) failure — caught here so it can't abort creation —
    // but does NOT rethrow on a post-insert fetch failure (rows are safe; the
    // next checklistFor/init read repopulates). Either way the trip returns.
    try {
      await seedChecklistForTrip(trip.id);
    } catch (e) {
      _lastError = 'Trip created, checklist seed failed: $e';
    }

    // Also non-fatal, same reasoning as the checklist seed above: the trip is
    // already committed, so a failed budget seed just leaves plannedByCategory
    // to fall back on its read-time vibe default.
    try {
      await seedCategoryBudgetsForTrip(trip.id);
    } catch (e) {
      _lastError = 'Trip created, budget seed failed: $e';
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

  /// Seeds the pre-trip checklist from the domestic/international template for
  /// the trip's location. Path B: seed and fetch are separate concerns.
  ///
  /// The insert MUST succeed — a failure there means no checklist exists, so it
  /// rethrows (createTrip catches it as non-fatal). The follow-up fetch is a
  /// nice-to-have: the rows are already committed to the DB, so a fetch failure
  /// leaves the cache empty and just surfaces via [error]; the next init/read
  /// repopulates it. No rethrow, no rollback on the fetch leg.
  Future<void> seedChecklistForTrip(String tripId) async {
    final trip = _trips[tripId];
    if (trip == null) return;

    final seeds = checklistTemplateFor(trip.location);
    if (seeds.isEmpty) {
      _checklistByTrip[tripId] = [];
      notifyListeners();
      return;
    }

    final insertPayload = seeds
        .map((s) => {
              'trip_id': tripId,
              'section': s.section,
              'title': s.title,
              'sort_order': s.sortOrder,
              'due_date_offset_days': s.dueDateOffsetDays,
            })
        .toList();

    // Seeding must succeed — rethrow on failure.
    try {
      await _supabase.from('trip_checklist_items').insert(insertPayload);
    } catch (e) {
      _lastError = 'Failed to seed checklist: $e';
      notifyListeners();
      rethrow;
    }

    // Fetch is a nice-to-have — rows are already committed to the DB. If the
    // fetch fails, the cache stays empty and the next read repopulates it. No
    // rethrow, no rollback.
    try {
      final rows = await _supabase
          .from('trip_checklist_items')
          .select()
          .eq('trip_id', tripId)
          .order('section')
          .order('sort_order');
      _checklistByTrip[tripId] =
          rows.map((r) => TripChecklistItem.fromJson(r)).toList();
    } catch (e) {
      _lastError = 'Checklist seeded but not loaded: $e';
    }

    notifyListeners();
  }

  /// Seeds the per-category planned budget from the trip's vibe-based default
  /// split ([plannedBudgetFor]) — the "planned" source for the Summary chart.
  ///
  /// Like [seedChecklistForTrip], the insert MUST succeed — a failure means no
  /// planned rows exist, so it rethrows (createTrip catches it as non-fatal).
  /// Unlike the checklist there's no follow-up fetch: planned_vnd is client-
  /// computed (not trigger-set), so the cache is populated straight from the
  /// same map that was inserted.
  Future<void> seedCategoryBudgetsForTrip(String tripId) async {
    final trip = _trips[tripId];
    if (trip == null) return;

    final planned = plannedBudgetFor(trip.vibe, trip.budgetVnd);

    final insertPayload = planned.entries
        .map((e) => {
              'trip_id': tripId,
              'category': e.key,
              'planned_vnd': e.value,
            })
        .toList();

    try {
      await _supabase.from('trip_category_budgets').insert(insertPayload);
    } catch (e) {
      _lastError = 'Failed to seed category budgets: $e';
      notifyListeners();
      rethrow;
    }

    _plannedByTrip[tripId] = Map<String, int>.from(planned);
    notifyListeners();
  }

  /// Toggles an item's checked state. Optimistic write, then a reconciliation
  /// read of the row the DB actually holds (updated_at is trigger-set server-
  /// side — we read it back rather than predicting a timestamp locally). Both
  /// the optimistic and reconciliation writes go through
  /// [_updateLocalChecklistItem]; the rollback stays inline because it restores
  /// the original snapshot at a known index rather than matching by id.
  Future<void> toggleChecklistItem(String itemId) async {
    final loc = _locateChecklistItem(itemId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _checklistByTrip[tripId]![index];
    final next = !old.isChecked;

    // Optimistic write path.
    _updateLocalChecklistItem(tripId, old.copyWith(isChecked: next));

    try {
      await _supabase
          .from('trip_checklist_items')
          .update({'is_checked': next}).eq('id', itemId);

      // Reconciliation write path: adopt the DB's own row (with its trigger-set
      // updated_at) instead of trusting the optimistic guess.
      final rows = await _supabase
          .from('trip_checklist_items')
          .select()
          .eq('id', itemId)
          .limit(1);
      if (rows.isNotEmpty) {
        _updateLocalChecklistItem(
            tripId, TripChecklistItem.fromJson(rows.first));
      }
    } catch (e) {
      _checklistByTrip[tripId]![index] = old; // rollback (inline, by snapshot)
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
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

  /// Finds (tripId, index) for a checklist item across the cache, or null.
  (String, int)? _locateChecklistItem(String itemId) {
    for (final entry in _checklistByTrip.entries) {
      final i = entry.value.indexWhere((c) => c.id == itemId);
      if (i != -1) return (entry.key, i);
    }
    return null;
  }

  /// Replaces a checklist item in the cache by id and notifies. No-op if the
  /// trip or item isn't cached. Used by both the optimistic and reconciliation
  /// write paths in [toggleChecklistItem].
  void _updateLocalChecklistItem(String tripId, TripChecklistItem updated) {
    final list = _checklistByTrip[tripId];
    if (list == null) return;
    final idx = list.indexWhere((i) => i.id == updated.id);
    if (idx < 0) return;
    list[idx] = updated;
    notifyListeners();
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

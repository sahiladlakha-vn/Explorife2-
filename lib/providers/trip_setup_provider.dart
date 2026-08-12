import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_document.dart';
import '../models/packing_item.dart';
import '../models/trip_traveler.dart';

// Owns all three of the Trip segment's cards: documents, packing items, and
// travelers. Travelers is read-only (no add/remove mutator — Phase 3's spec
// has no invite flow, just a rendered list), the other two are optimistic
// read/write like BookingProvider. Registered as a PLAIN
// ChangeNotifierProvider — NOT a proxy: document/packing reads are scoped by
// trip_id and enforced server-side by RLS (trip_documents_via_trip /
// trip_packing_items_via_trip), so this provider needs no client-side userId
// and no AuthProvider dependency. The travelers join needs the trip's
// owner_id, which the caller already has (TripProvider) and passes in as a
// loadSetup parameter — kept that way rather than depending on TripProvider
// directly, so the two providers stay decoupled.
//
//   Registration (lib/main.dart, one line among the plain providers):
//     ChangeNotifierProvider(create: (_) => TripSetupProvider(
//         supabase: Supabase.instance.client)),
//
//   clear() must be called at both sign-out sites (profile_screen.dart,
//   side_drawer.dart), alongside the existing BookingProvider.clear() calls.
class TripSetupProvider extends ChangeNotifier {
  TripSetupProvider({required SupabaseClient supabase}) : _supabase = supabase;

  final SupabaseClient _supabase;

  // Caches keyed by tripId (mirrors BookingProvider._byTrip). Key present
  // with an empty list == "fetched, none"; a MISSING key == "never fetched".
  final Map<String, List<TripDocument>> _documentsByTrip = {};
  final Map<String, List<PackingItem>> _packingByTrip = {};
  final Map<String, List<TripTraveler>> _travelersByTrip = {};

  // Per-trip fetch state, same reasoning as BookingProvider: the Overview
  // card and the My Trip tab may watch different trip ids and shouldn't
  // thrash a shared flag. One flag/error pair covers all three caches since
  // loadSetup fetches them together.
  final Map<String, bool> _loadingByTrip = {};
  final Map<String, String?> _errorByTrip = {};

  int _tempSeq = 0;

  // ── Pure reads (safe in build()) ────────────────────────────────────────
  List<TripDocument> documentsFor(String tripId) =>
      _documentsByTrip[tripId] ?? const <TripDocument>[];
  List<PackingItem> packingFor(String tripId) =>
      _packingByTrip[tripId] ?? const <PackingItem>[];
  List<TripTraveler> travelersFor(String tripId) =>
      _travelersByTrip[tripId] ?? const <TripTraveler>[];
  bool isLoadingFor(String tripId) => _loadingByTrip[tripId] ?? false;
  String? errorFor(String tripId) => _errorByTrip[tripId];
  bool hasLoaded(String tripId) => _documentsByTrip.containsKey(tripId);

  /// Packed / total, for the Packing card's "X / Y packed" header + progress
  /// bar. Pure derivation — no separate cached counter to keep in sync.
  (int packed, int total) packingProgress(String tripId) {
    final items = packingFor(tripId);
    return (items.where((i) => i.isPacked).length, items.length);
  }

  // ── Fetch ─────────────────────────────────────────────────────────────
  /// [ownerId] is the trip's `owner_id` (TripProvider already holds this —
  /// see the class doc for why it's a parameter here rather than a lookup).
  /// TripProvider.createTrip() gives the owner a real trip_collaborators row
  /// (permission='edit') alongside every new trip, and the backfill
  /// migration (20260806000400) did the same for pre-existing trips — so
  /// [ownerId] is normally just used to label that row Organizer rather than
  /// Member. It's kept as a defensive fallback too (see below) for the rare
  /// trip that predates both.
  Future<void> loadSetup(String tripId,
      {required String ownerId, bool force = false}) async {
    if (!force && (hasLoaded(tripId) || (_loadingByTrip[tripId] ?? false))) {
      return;
    }

    _loadingByTrip[tripId] = true;
    _errorByTrip[tripId] = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _supabase
            .from('trip_documents')
            .select()
            .eq('trip_id', tripId)
            .order('expires_on', ascending: true, nullsFirst: false)
            .order('created_at', ascending: true),
        _supabase
            .from('trip_packing_items')
            .select()
            .eq('trip_id', tripId)
            .order('sort_order', ascending: true),
        _supabase.from('trip_collaborators').select().eq('trip_id', tripId),
      ]);
      _documentsByTrip[tripId] = (results[0] as List)
          .map((e) => TripDocument.fromJson(e as Map<String, dynamic>))
          .toList();
      _packingByTrip[tripId] = (results[1] as List)
          .map((e) => PackingItem.fromJson(e as Map<String, dynamic>))
          .toList();

      // Second leg: resolve display names. Runs after the Future.wait above
      // (not inside it) because it needs the collaborator rows' user_ids
      // first — the ids to look up aren't known until that query returns.
      final collabRows = results[2] as List;
      final userIds = {
        ownerId,
        for (final r in collabRows) r['user_id'] as String,
      };
      final profileRows = await _supabase
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', userIds.toList());
      final profileById = {
        for (final p in profileRows) p['id'] as String: p,
      };

      String nameFor(String userId) =>
          (profileById[userId]?['display_name'] as String?) ?? 'Traveler';
      String? avatarFor(String userId) =>
          profileById[userId]?['avatar_url'] as String?;

      // One uniform source now — every collaborator row (including the
      // owner's own, per the class doc) maps straight to a TripTraveler.
      // Role is just a label over that same id space: `user_id == ownerId`
      // reads Organizer, everyone else reads Member. This is what makes the
      // owner assignable in the Documents/Packing pickers — their `id` here
      // is a real trip_collaborators.id, not a synthesized user id.
      final hasOwnerRow = collabRows.any((r) => r['user_id'] == ownerId);
      final travelers = [
        for (final r in collabRows)
          TripTraveler(
            id: r['id'] as String,
            userId: r['user_id'] as String,
            displayName: nameFor(r['user_id'] as String),
            avatarUrl: avatarFor(r['user_id'] as String),
            role: r['user_id'] == ownerId
                ? TravelerRole.organizer
                : TravelerRole.member,
            status: TravelerStatus.fromWire(r['status'] as String?),
          ),
        // Defensive fallback for a trip predating both the backfill and
        // createTrip's own insert — keeps the Organizer visible even without
        // a real row. This synthesized row's `id` isn't a real
        // trip_collaborators id, so it still can't be picked as an
        // assignee/document-owner; that's an acceptable gap for a
        // not-yet-backfilled trip, not the common case.
        if (!hasOwnerRow)
          TripTraveler(
            id: ownerId,
            userId: ownerId,
            displayName: nameFor(ownerId),
            avatarUrl: avatarFor(ownerId),
            role: TravelerRole.organizer,
            status: TravelerStatus.confirmed,
          ),
      ];
      // Organizer always leads, regardless of row insertion order.
      travelers.sort((a, b) => a.role == b.role
          ? 0
          : (a.role == TravelerRole.organizer ? -1 : 1));
      _travelersByTrip[tripId] = travelers;
    } catch (e) {
      // Leave all three caches ABSENT for this trip (hasLoaded stays false)
      // — matches BookingProvider's {hasLoaded:false, errorFor != null} state.
      _errorByTrip[tripId] = e.toString();
    } finally {
      _loadingByTrip[tripId] = false;
      notifyListeners();
    }
  }

  // ── Packing mutators ────────────────────────────────────────────────────

  /// Optimistic toggle, rollback on failure — same shape as
  /// TripProvider.toggleChecklistItem, but no reconciliation read (is_packed
  /// has no server-computed field to adopt back, unlike updated_at there).
  Future<void> togglePacked(String itemId) async {
    final loc = _locatePacking(itemId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _packingByTrip[tripId]![index];
    final next = !old.isPacked;

    _packingByTrip[tripId]![index] = old.copyWith(isPacked: next);
    notifyListeners();

    try {
      await _supabase
          .from('trip_packing_items')
          .update({'is_packed': next}).eq('id', itemId);
    } catch (e) {
      _packingByTrip[tripId]![index] = old; // rollback
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Optimistic temp-id insert, then reconcile to the server row — matches
  /// BookingProvider.add / TripProvider.addStop.
  Future<PackingItem> addPackingItem({
    required String tripId,
    String? assigneeCollaboratorId,
    required String label,
    String? category,
    int quantity = 1,
  }) async {
    final sortOrder = packingFor(tripId).length;
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}-${_tempSeq++}';
    final optimistic = PackingItem(
      id: tempId,
      tripId: tripId,
      assigneeCollaboratorId: assigneeCollaboratorId,
      label: label,
      category: category,
      quantity: quantity,
      sortOrder: sortOrder,
      createdAt: DateTime.now(),
    );
    _packingByTrip[tripId] = [...?_packingByTrip[tripId], optimistic];
    notifyListeners();

    try {
      final row = await _supabase
          .from('trip_packing_items')
          .insert({
            'trip_id': tripId,
            'assignee_collaborator_id': assigneeCollaboratorId,
            'label': label,
            'category': category,
            'quantity': quantity,
            'sort_order': sortOrder,
          })
          .select()
          .single();
      final saved = PackingItem.fromJson(row);
      _packingByTrip[tripId] = _packingByTrip[tripId]!
          .map((i) => i.id == tempId ? saved : i)
          .toList();
      notifyListeners();
      return saved;
    } catch (e) {
      _packingByTrip[tripId] =
          _packingByTrip[tripId]!.where((i) => i.id != tempId).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removePackingItem(String itemId) async {
    final loc = _locatePacking(itemId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final removed = _packingByTrip[tripId]![index];

    _packingByTrip[tripId]!.removeAt(index);
    notifyListeners();

    try {
      await _supabase.from('trip_packing_items').delete().eq('id', itemId);
    } catch (e) {
      _packingByTrip[tripId]!.insert(index, removed); // rollback to position
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Document mutators ────────────────────────────────────────────────────

  Future<TripDocument> addDocument({
    required String tripId,
    String? ownerCollaboratorId,
    required DocumentType type,
    required String title,
    String? fileUrl,
    DateTime? expiresOn,
  }) async {
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}-${_tempSeq++}';
    final optimistic = TripDocument(
      id: tempId,
      tripId: tripId,
      ownerCollaboratorId: ownerCollaboratorId,
      type: type,
      title: title,
      fileUrl: fileUrl,
      expiresOn: expiresOn,
      createdAt: DateTime.now(),
    );
    _documentsByTrip[tripId] = [...?_documentsByTrip[tripId], optimistic];
    notifyListeners();

    try {
      final row = await _supabase
          .from('trip_documents')
          .insert({
            'trip_id': tripId,
            'owner_collaborator_id': ownerCollaboratorId,
            'type': type.wire,
            'title': title,
            'file_url': fileUrl,
            'expires_on': expiresOn?.toIso8601String().substring(0, 10),
          })
          .select()
          .single();
      final saved = TripDocument.fromJson(row);
      _documentsByTrip[tripId] = _documentsByTrip[tripId]!
          .map((d) => d.id == tempId ? saved : d)
          .toList();
      notifyListeners();
      return saved;
    } catch (e) {
      _documentsByTrip[tripId] =
          _documentsByTrip[tripId]!.where((d) => d.id != tempId).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeDocument(String documentId) async {
    final loc = _locateDocument(documentId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final removed = _documentsByTrip[tripId]![index];

    _documentsByTrip[tripId]!.removeAt(index);
    notifyListeners();

    try {
      await _supabase.from('trip_documents').delete().eq('id', documentId);
    } catch (e) {
      _documentsByTrip[tripId]!.insert(index, removed); // rollback to position
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Traveler mutators ────────────────────────────────────────────────────

  /// Inserts a real trip_collaborators row for [userId] (owner-only per RLS —
  /// trip_collaborators_insert_by_owner) and appends the resulting
  /// TripTraveler locally. Unlike loadSetup's join, display name/avatar are
  /// already known from the caller's lookup (TravelerLookupSheet resolves
  /// them via find_user_by_identifier), so no second profiles query is
  /// needed here. A duplicate [userId] for this trip fails on the
  /// (trip_id, user_id) primary key — surfaced via the same rollback path as
  /// any other failure, not specially handled.
  Future<TripTraveler> addTraveler({
    required String tripId,
    required String userId,
    required String displayName,
    String? avatarUrl,
    String permission = 'edit',
  }) async {
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}-${_tempSeq++}';
    final optimistic = TripTraveler(
      id: tempId,
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      role: TravelerRole.member,
      status: TravelerStatus.confirmed,
    );
    _travelersByTrip[tripId] = [...?_travelersByTrip[tripId], optimistic];
    notifyListeners();

    try {
      final row = await _supabase
          .from('trip_collaborators')
          .insert({
            'trip_id': tripId,
            'user_id': userId,
            'permission': permission,
            'status': 'confirmed',
          })
          .select()
          .single();
      final saved = TripTraveler(
        id: row['id'] as String,
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        role: TravelerRole.member,
        status: TravelerStatus.fromWire(row['status'] as String?),
      );
      _travelersByTrip[tripId] = _travelersByTrip[tripId]!
          .map((t) => t.id == tempId ? saved : t)
          .toList();
      notifyListeners();
      return saved;
    } catch (e) {
      _travelersByTrip[tripId] =
          _travelersByTrip[tripId]!.where((t) => t.id != tempId).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Sign-out ─────────────────────────────────────────────────────────────
  void clear() {
    _documentsByTrip.clear();
    _packingByTrip.clear();
    _travelersByTrip.clear();
    _loadingByTrip.clear();
    _errorByTrip.clear();
    notifyListeners();
  }

  // ── Internal helpers ─────────────────────────────────────────────────────
  (String, int)? _locatePacking(String itemId) {
    for (final entry in _packingByTrip.entries) {
      final i = entry.value.indexWhere((it) => it.id == itemId);
      if (i != -1) return (entry.key, i);
    }
    return null;
  }

  (String, int)? _locateDocument(String documentId) {
    for (final entry in _documentsByTrip.entries) {
      final i = entry.value.indexWhere((d) => d.id == documentId);
      if (i != -1) return (entry.key, i);
    }
    return null;
  }
}

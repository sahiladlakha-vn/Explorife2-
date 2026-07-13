import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_booking.dart';

// Owns trip bookings (flights/stays/activities/transport) per trip. Registered as
// a PLAIN ChangeNotifierProvider — NOT a proxy: reads are scoped by trip_id and
// enforced server-side by RLS (trip_bookings_via_trip), so this provider needs no
// client-side userId and no AuthProvider dependency. The only user id it touches
// is `created_by` on insert, taken as a per-call parameter. That designs out the
// owner_id:'' auth-race bug class at the signature rather than guarding against it.
//
//   Registration (lib/main.dart, one line among the plain providers):
//     ChangeNotifierProvider(create: (_) => BookingProvider(
//         supabase: Supabase.instance.client)),
class BookingProvider extends ChangeNotifier {
  BookingProvider({required SupabaseClient supabase}) : _supabase = supabase;

  final SupabaseClient _supabase;

  // Cache keyed by tripId (mirrors TripProvider._stopsByTrip). Key present with an
  // empty list == "fetched, no bookings"; a MISSING key == "never fetched" — that
  // missing-key state is the refetch sentinel, so an empty trip isn't re-queried
  // on every rebuild.
  final Map<String, List<TripBooking>> _byTrip = {};

  // Per-trip fetch state — a deliberate divergence from TripProvider's single
  // _isLoading/_lastError, so the Overview card and the My Trip tab (potentially
  // different trip ids) can't thrash a shared flag.
  final Map<String, bool> _loadingByTrip = {};
  final Map<String, String?> _errorByTrip = {};

  // Monotonic suffix so two temp ids minted in the same microsecond can't collide.
  int _tempSeq = 0;

  // ── Pure reads (safe in build()) ────────────────────────────────────────────
  List<TripBooking> bookingsFor(String tripId) =>
      _byTrip[tripId] ?? const <TripBooking>[];
  bool isLoadingFor(String tripId) => _loadingByTrip[tripId] ?? false;
  String? errorFor(String tripId) => _errorByTrip[tripId];
  bool hasLoaded(String tripId) => _byTrip.containsKey(tripId);

  // ── Fetch ───────────────────────────────────────────────────────────────────
  Future<void> fetchForTrip(String tripId, {bool force = false}) async {
    // Idempotent: skip when already loaded or a fetch is in flight (unless forced).
    if (!force && (hasLoaded(tripId) || (_loadingByTrip[tripId] ?? false))) return;

    _loadingByTrip[tripId] = true;
    _errorByTrip[tripId] = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('trip_bookings')
          .select()
          .eq('trip_id', tripId) // RLS owns ownership; no userId filter, no ''.
          .order('start_at', ascending: true, nullsFirst: false)
          .order('created_at', ascending: true); // stable secondary sort
      _byTrip[tripId] = (rows as List)
          .map((e) => TripBooking.fromJson(e as Map<String, dynamic>))
          .toList();
      _sortInPlace(tripId); // belt-and-braces; server already ordered this way
    } catch (e) {
      // Leave _byTrip[tripId] ABSENT (hasLoaded stays false) and record the error.
      // {hasLoaded:false, errorFor != null} is an intentional, renderable state —
      // Phase 3 shows an error+retry, never a forever-spinner.
      _errorByTrip[tripId] = e.toString();
    } finally {
      _loadingByTrip[tripId] = false;
      notifyListeners();
    }
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  /// Optimistic temp-id insert, then reconcile to the server row (matches
  /// TripProvider.addStop). `createdBy` is passed straight to the SET NULL column
  /// — NEVER coerced to '' (null when signed out). If the caller is genuinely
  /// signed out, the trip-ownership RLS policy refuses the insert; that rejection
  /// is caught, the optimistic row rolled back, the error recorded in
  /// _errorByTrip, and rethrown so the submitting UI can surface it.
  Future<TripBooking> add({
    required String tripId,
    String? stopId,
    required BookingType bookingType,
    required String title,
    String? confirmationRef,
    String? provider,
    DateTime? startAt,
    DateTime? endAt,
    int? amountVnd, // null = TBD, preserved end-to-end (no ?? 0)
    BookingStatus status = BookingStatus.toBook,
    required String? createdBy, // null, never ''
  }) async {
    final tempId = _newTempId();
    final optimistic = TripBooking(
      id: tempId,
      tripId: tripId,
      stopId: stopId,
      bookingType: bookingType,
      title: title,
      confirmationRef: confirmationRef,
      provider: provider,
      startAt: startAt,
      endAt: endAt,
      amountVnd: amountVnd,
      status: status,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    _byTrip[tripId] = [...?_byTrip[tripId], optimistic];
    _sortInPlace(tripId);
    notifyListeners();

    try {
      final row = await _supabase
          .from('trip_bookings')
          .insert({
            'trip_id': tripId,
            'stop_id': stopId,
            'booking_type': bookingType.wire,
            'title': title,
            'confirmation_ref': confirmationRef,
            'provider': provider,
            'start_at': startAt?.toUtc().toIso8601String(),
            'end_at': endAt?.toUtc().toIso8601String(),
            'amount_vnd': amountVnd,
            'status': status.wire,
            'created_by': createdBy,
          })
          .select()
          .single();
      final saved = TripBooking.fromJson(row);
      _byTrip[tripId] =
          _byTrip[tripId]!.map((b) => b.id == tempId ? saved : b).toList();
      _sortInPlace(tripId);
      notifyListeners();
      return saved;
    } catch (e) {
      _byTrip[tripId] =
          _byTrip[tripId]!.where((b) => b.id != tempId).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Optimistic status flip (pill tap) with rollback. Order is unaffected by
  /// status, so no re-sort.
  Future<void> updateStatus(String bookingId, BookingStatus status) async {
    final loc = _locate(bookingId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _byTrip[tripId]![index];

    _byTrip[tripId] = _byTrip[tripId]!
        .map((b) => b.id == bookingId ? b.copyWith(status: status) : b)
        .toList();
    notifyListeners();

    if (_isTemp(bookingId)) return; // never PATCH an id the server hasn't seen

    try {
      await _supabase
          .from('trip_bookings')
          .update({'status': status.wire}).eq('id', bookingId);
    } catch (e) {
      _byTrip[tripId] =
          _byTrip[tripId]!.map((b) => b.id == bookingId ? old : b).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Optimistic amount edit with rollback. Delegates to copyWith(amountVnd:),
  /// where passing `null` clears to TBD and the sentinel keeps 0 ≠ null — the
  /// money contract survives the mutation path.
  Future<void> updateAmount(String bookingId, int? amountVnd) async {
    final loc = _locate(bookingId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _byTrip[tripId]![index];

    _byTrip[tripId] = _byTrip[tripId]!
        .map((b) => b.id == bookingId ? b.copyWith(amountVnd: amountVnd) : b)
        .toList();
    notifyListeners();

    if (_isTemp(bookingId)) return;

    try {
      await _supabase
          .from('trip_bookings')
          .update({'amount_vnd': amountVnd}).eq('id', bookingId);
    } catch (e) {
      _byTrip[tripId] =
          _byTrip[tripId]!.map((b) => b.id == bookingId ? old : b).toList();
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// General edit for the fuller form. All fields optional. KNOWN LIMITATION
  /// (same as TripBooking.copyWith): only amountVnd has a sentinel, so this can
  /// SET nullable text/date fields but can't CLEAR them back to null. The PATCH
  /// carries only the provided (non-null) fields, mirroring that preserve-on-null
  /// semantics so we never null a column we didn't mean to touch.
  Future<void> update(
    String bookingId, {
    String? title,
    String? confirmationRef,
    String? provider,
    DateTime? startAt,
    DateTime? endAt,
    BookingType? bookingType,
    String? stopId,
  }) async {
    final loc = _locate(bookingId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final old = _byTrip[tripId]![index];

    _byTrip[tripId] = _byTrip[tripId]!.map((b) {
      if (b.id != bookingId) return b;
      return b.copyWith(
        title: title,
        confirmationRef: confirmationRef,
        provider: provider,
        startAt: startAt,
        endAt: endAt,
        bookingType: bookingType,
        stopId: stopId,
      );
    }).toList();
    _sortInPlace(tripId); // start_at may have changed
    notifyListeners();

    if (_isTemp(bookingId)) return;

    final patch = <String, dynamic>{
      if (title != null) 'title': title,
      if (confirmationRef != null) 'confirmation_ref': confirmationRef,
      if (provider != null) 'provider': provider,
      if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
      if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
      if (bookingType != null) 'booking_type': bookingType.wire,
      if (stopId != null) 'stop_id': stopId,
    };
    if (patch.isEmpty) return;

    try {
      await _supabase.from('trip_bookings').update(patch).eq('id', bookingId);
    } catch (e) {
      _byTrip[tripId] =
          _byTrip[tripId]!.map((b) => b.id == bookingId ? old : b).toList();
      _sortInPlace(tripId);
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Optimistic delete with rollback-to-position.
  Future<void> remove(String bookingId) async {
    final loc = _locate(bookingId);
    if (loc == null) return;
    final (tripId, index) = loc;
    final removed = _byTrip[tripId]![index];

    _byTrip[tripId]!.removeAt(index);
    notifyListeners();

    if (_isTemp(bookingId)) return; // never persisted; nothing to delete

    try {
      await _supabase.from('trip_bookings').delete().eq('id', bookingId);
    } catch (e) {
      _byTrip[tripId]!.insert(index, removed);
      _sortInPlace(tripId);
      _errorByTrip[tripId] = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Drop all cached bookings and per-trip state. A plain provider persists
  /// across auth changes (it doesn't rebuild like the TripProvider proxy).
  /// Cross-account leakage is already impossible — the cache is keyed by trip_id
  /// and RLS blocks reads of another user's trips — so this is memory hygiene.
  /// PHASE 3 WIRING: call this alongside AuthProvider.signOut() at both sign-out
  /// sites — profile_screen.dart (_confirmSignOut) and side_drawer.dart.
  void clear() {
    _byTrip.clear();
    _loadingByTrip.clear();
    _errorByTrip.clear();
    notifyListeners();
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  // Obviously-fake, collision-proof temp id. _isTemp gates every mutation so a
  // still-optimistic row never fires a PATCH/DELETE on an id the server has never
  // seen — closing half the insert-race window cheaply.
  String _newTempId() =>
      'temp_${DateTime.now().microsecondsSinceEpoch}_${_tempSeq++}';
  static bool _isTemp(String id) => id.startsWith('temp_');

  void _sortInPlace(String tripId) {
    _byTrip[tripId]?.sort(_compare);
  }

  // start_at ascending with nulls LAST, then created_at ascending as a stable
  // secondary so null-dated bookings don't reorder between fetches. Mirrors the
  // server .order() chain in fetchForTrip.
  int _compare(TripBooking a, TripBooking b) {
    final sa = a.startAt, sb = b.startAt;
    if (sa == null && sb != null) return 1;
    if (sa != null && sb == null) return -1;
    if (sa != null && sb != null) {
      final c = sa.compareTo(sb);
      if (c != 0) return c;
    }
    return a.createdAt.compareTo(b.createdAt);
  }

  // Locate a booking across the per-trip map → (tripId, index). Mutations take
  // only a bookingId while the cache is bucketed by trip.
  (String, int)? _locate(String bookingId) {
    for (final entry in _byTrip.entries) {
      final i = entry.value.indexWhere((b) => b.id == bookingId);
      if (i != -1) return (entry.key, i);
    }
    return null;
  }
}

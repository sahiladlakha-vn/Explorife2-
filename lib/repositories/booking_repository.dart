import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_booking.dart';

/// The **only** Supabase-aware file in the bookings domain — mirrors
/// GemRepository's role (Presentation → State → Repository → Data layering;
/// see lib/repositories/gem_repository.dart's own doc for the pattern this
/// follows). Plain CRUD, JSON in/out — every optimistic-update/rollback
/// decision stays in BookingProvider; this file only knows how to talk to
/// Postgres, which is what makes BookingProvider testable with a fake here
/// instead of a real network call.
class BookingRepository {
  BookingRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'trip_bookings';

  /// All bookings for [tripId], ordered start_at ascending (nulls last), then
  /// created_at ascending as a stable secondary — matches
  /// BookingProvider's own in-memory re-sort so a fetch and a later optimistic
  /// insert never disagree about order.
  Future<List<TripBooking>> fetchForTrip(String tripId) async {
    final rows = await _db
        .from(table)
        .select()
        .eq('trip_id', tripId) // RLS owns ownership; no userId filter, no ''.
        .order('start_at', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((e) => TripBooking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Inserts a new booking and returns the persisted row (DB-assigned id and
  /// timestamp). Throws on failure so the caller can roll back its optimistic
  /// insert and surface the error.
  Future<TripBooking> insert({
    required String tripId,
    String? stopId,
    required BookingType bookingType,
    required String title,
    String? confirmationRef,
    String? provider,
    DateTime? startAt,
    DateTime? endAt,
    int? amountVnd,
    required BookingStatus status,
    required String? createdBy,
  }) async {
    final row = await _db
        .from(table)
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
    return TripBooking.fromJson(row);
  }

  /// Applies a pre-built column patch to one booking. The caller (provider)
  /// owns deciding which columns belong in [fields] — including the
  /// sentinel-vs-omit decision for nullable columns — this just sends it.
  Future<void> patch(String bookingId, Map<String, dynamic> fields) async {
    await _db.from(table).update(fields).eq('id', bookingId);
  }

  /// Deletes one booking. Errors (including "already gone") propagate to the
  /// caller, which rolls its optimistic removal back on any failure.
  Future<void> delete(String bookingId) async {
    await _db.from(table).delete().eq('id', bookingId);
  }
}

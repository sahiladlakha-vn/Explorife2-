import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attraction.dart';

/// The Supabase-aware layer for `attractions` — mirrors TourRepository's
/// layering. RLS (not client-side filtering) is what actually scopes
/// ownership/visibility here — see the migration's policies — this class
/// just shapes the queries.
class AttractionRepository {
  AttractionRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'attractions';

  /// The public feed — RLS already restricts this to verified,
  /// not-retracted listings for non-owners/non-admins, but the explicit
  /// filter keeps the query's own intent honest even for an owner/admin
  /// session that could technically see more.
  Future<List<Attraction>> fetchVerified({String? category}) async {
    try {
      var query = _db
          .from(table)
          .select()
          .eq('verification_status', 'verified')
          .filter('deleted_at', 'is', null);
      if (category != null) query = query.eq('category', category);
      final data = await query.order('created_at', ascending: false);
      return (data as List)
          .map((e) => Attraction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AttractionRepository.fetchVerified error: $e');
      return [];
    }
  }

  Future<Attraction?> fetchById(String id) async {
    try {
      final data = await _db.from(table).select().eq('id', id).maybeSingle();
      return data == null ? null : Attraction.fromJson(data);
    } catch (e) {
      debugPrint('AttractionRepository.fetchById error: $e');
      return null;
    }
  }

  /// A Gem's linked Attraction, if one exists, is verified, and is not
  /// retracted — the query Gem Detail's additional section runs. Null (not
  /// an error) when no business has claimed/verified this place yet.
  Future<Attraction?> fetchVerifiedForGem(String gemId) async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('gem_id', gemId)
          .eq('verification_status', 'verified')
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      return data == null ? null : Attraction.fromJson(data);
    } catch (e) {
      debugPrint('AttractionRepository.fetchVerifiedForGem error: $e');
      return null;
    }
  }

  /// The signed-in Business Owner's own listings, any verification status
  /// — relies on RLS's "owners can view own attractions" policy.
  Future<List<Attraction>> fetchOwnedByCurrentUser() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('owner_id', userId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => Attraction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AttractionRepository.fetchOwnedByCurrentUser error: $e');
      return [];
    }
  }

  /// The moderation queue — relies on RLS's "admins can view all
  /// attractions" policy (a non-admin session gets an empty list, not an
  /// error, since the underlying query itself is the same either way).
  Future<List<Attraction>> fetchPending() async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('verification_status', 'pending')
          .order('created_at', ascending: true);
      return (data as List)
          .map((e) => Attraction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AttractionRepository.fetchPending error: $e');
      return [];
    }
  }

  Future<Attraction> create(Attraction attraction) async {
    final inserted =
        await _db.from(table).insert(attraction.toInsert()).select().single();
    return Attraction.fromJson(inserted);
  }

  /// Verification-status fields are deliberately excluded from this
  /// payload — see the DB trigger's own doc comment for why an owner's
  /// plain update can never touch them regardless of what a client sends.
  Future<void> update(Attraction attraction) async {
    await _db.from(table).update(attraction.toInsert()).eq('id', attraction.id);
  }

  /// The only sanctioned way to approve/reject a listing — calls the
  /// `verify_attraction` RPC (security definer: checks the caller is
  /// admin-tier, updates the row, AND writes a real admin_action_log
  /// entry in one transaction). Throws (surfacing the RPC's own exception
  /// message) if the caller isn't Content Moderator/Regional Admin/Super
  /// Admin.
  Future<Attraction> verify(String attractionId, {required bool approve}) async {
    final data = await _db.rpc('verify_attraction', params: {
      'p_attraction_id': attractionId,
      'p_approve': approve,
    });
    return Attraction.fromJson(data as Map<String, dynamic>);
  }

  /// Soft-deletes a listing — the owner (any time, any status) or an
  /// admin-tier account (moderation power) may call this; anyone else's
  /// call is rejected by the RPC itself. Only logs to admin_action_log
  /// when the caller is admin-tier, not for an owner retracting their own
  /// listing — see the RPC's own doc comment for why.
  Future<Attraction> retract(String attractionId) async {
    final data = await _db
        .rpc('retract_attraction', params: {'p_attraction_id': attractionId});
    return Attraction.fromJson(data as Map<String, dynamic>);
  }
}

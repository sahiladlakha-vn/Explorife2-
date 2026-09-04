import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/restaurant.dart';

/// Defense-in-depth for any "this business listing is currently live"
/// query — same reasoning as Attraction's own liveVerifiedAttraction (see
/// lib/repositories/attraction_repository.dart): retract_restaurant sets
/// deleted_at but deliberately does NOT change verification_status, so a
/// query that only checks verification_status can still return a
/// retracted row. The primary defense is the query filter itself
/// (`.filter('deleted_at', 'is', null)`); this is the belt-and-suspenders
/// backstop applied proactively here (Attraction only got this after a
/// second review pass found the gap — see the Attraction audit doc's
/// "Post-review fix 2").
Restaurant? liveVerifiedRestaurant(Restaurant? restaurant) {
  if (restaurant == null) return null;
  if (restaurant.isRetracted) return null;
  if (restaurant.verificationStatus != RestaurantVerificationStatus.verified) {
    return null;
  }
  return restaurant;
}

/// The Supabase-aware layer for `restaurants` (+ `restaurant_menu_items`)
/// — mirrors AttractionRepository's layering exactly. RLS (not
/// client-side filtering) is what actually scopes ownership/visibility;
/// this class just shapes the queries.
class RestaurantRepository {
  RestaurantRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'restaurants';
  static const String menuItemsTable = 'restaurant_menu_items';

  /// The public feed — RLS already restricts this to verified,
  /// not-retracted listings for non-owners/non-admins, but the explicit
  /// filter keeps the query's own intent honest even for an owner/admin
  /// session that could technically see more.
  Future<List<Restaurant>> fetchVerified() async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('verification_status', 'verified')
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
          .where((r) => liveVerifiedRestaurant(r) != null)
          .toList();
    } catch (e) {
      debugPrint('RestaurantRepository.fetchVerified error: $e');
      return [];
    }
  }

  /// Deliberately NOT filtered by verification_status or deleted_at — this
  /// backs both the standalone public detail screen (RLS is what protects
  /// an anonymous/non-owner/non-admin viewer from seeing a retracted or
  /// unverified listing here) AND the owner's own view/edit/retract flow,
  /// which INTENTIONALLY needs to see the listing regardless of status.
  /// Do not add a filter here — that would break the owner's own view of
  /// their own listing (same reasoning as AttractionRepository.fetchById).
  Future<Restaurant?> fetchById(String id) async {
    try {
      final data = await _db.from(table).select().eq('id', id).maybeSingle();
      return data == null ? null : Restaurant.fromJson(data);
    } catch (e) {
      debugPrint('RestaurantRepository.fetchById error: $e');
      return null;
    }
  }

  /// A Gem's linked Restaurant, if one exists, is verified, AND is not
  /// retracted — the query Gem Detail's linked-business card runs. Both
  /// the query filter and [liveVerifiedRestaurant] guard against the same
  /// gap Attraction's fetchVerifiedForGem was fixed for: an owner/admin
  /// viewing their own Gem must not see a stale card for a listing they
  /// (or another admin) already retracted.
  Future<Restaurant?> fetchVerifiedForGem(String gemId) async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('gem_id', gemId)
          .eq('verification_status', 'verified')
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      return liveVerifiedRestaurant(data == null ? null : Restaurant.fromJson(data));
    } catch (e) {
      debugPrint('RestaurantRepository.fetchVerifiedForGem error: $e');
      return null;
    }
  }

  /// Deliberately NOT filtered by verification_status or deleted_at — same
  /// "show the owner their own history" intent as fetchById.
  Future<List<Restaurant>> fetchOwnedByCurrentUser() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('owner_id', userId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('RestaurantRepository.fetchOwnedByCurrentUser error: $e');
      return [];
    }
  }

  /// The moderation queue — relies on RLS's "admins can view all
  /// restaurants" policy. Filters deleted_at from the start: an owner can
  /// retract a listing at any verification status (including 'pending'),
  /// and a withdrawn submission shouldn't waste a moderator's attention —
  /// this is the exact bug the Attraction deleted_at audit found in
  /// fetchPending, applied here proactively rather than waiting to find it
  /// again.
  Future<List<Restaurant>> fetchPending() async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('verification_status', 'pending')
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: true);
      return (data as List)
          .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('RestaurantRepository.fetchPending error: $e');
      return [];
    }
  }

  Future<Restaurant> create(Restaurant restaurant) async {
    final inserted =
        await _db.from(table).insert(restaurant.toInsert()).select().single();
    return Restaurant.fromJson(inserted);
  }

  /// Verification-status fields are deliberately excluded from this
  /// payload — see the DB trigger's own doc comment for why an owner's
  /// plain update can never touch them regardless of what a client sends.
  Future<void> update(Restaurant restaurant) async {
    await _db.from(table).update(restaurant.toInsert()).eq('id', restaurant.id);
  }

  /// The only sanctioned way to approve/reject a listing — calls the
  /// `verify_restaurant` RPC (security definer, same shape as
  /// verify_attraction: checks the caller is admin-tier, updates the row,
  /// AND writes a real admin_action_log entry in one transaction).
  Future<Restaurant> verify(String restaurantId, {required bool approve}) async {
    final data = await _db.rpc('verify_restaurant', params: {
      'p_restaurant_id': restaurantId,
      'p_approve': approve,
    });
    return Restaurant.fromJson(data as Map<String, dynamic>);
  }

  /// Soft-deletes a listing — the owner (any time, any status) or an
  /// admin-tier account may call this; same shape as retract_attraction.
  Future<Restaurant> retract(String restaurantId) async {
    final data = await _db
        .rpc('retract_restaurant', params: {'p_restaurant_id': restaurantId});
    return Restaurant.fromJson(data as Map<String, dynamic>);
  }

  /// A restaurant's menu, in owner-controlled display order — visible
  /// under the same RLS scoping as the parent restaurant itself (public
  /// only for a verified/not-retracted restaurant; owner/admin see their
  /// own/all regardless — see the migration's policies).
  Future<List<RestaurantMenuItem>> fetchMenuItems(String restaurantId) async {
    try {
      final data = await _db
          .from(menuItemsTable)
          .select()
          .eq('restaurant_id', restaurantId)
          .order('display_order', ascending: true);
      return (data as List)
          .map((e) => RestaurantMenuItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('RestaurantRepository.fetchMenuItems error: $e');
      return [];
    }
  }

  /// Replaces a restaurant's entire menu with [items] — simpler than
  /// diffing individual dish edits for a form that always submits the
  /// whole list, and RLS's "owners can manage own restaurant menu items"
  /// policy already scopes both the delete and the insert to the caller's
  /// own restaurant.
  Future<void> replaceMenuItems(
      String restaurantId, List<RestaurantMenuItem> items) async {
    await _db.from(menuItemsTable).delete().eq('restaurant_id', restaurantId);
    if (items.isEmpty) return;
    await _db
        .from(menuItemsTable)
        .insert(items.map((i) => i.toInsert(restaurantId)).toList());
  }
}

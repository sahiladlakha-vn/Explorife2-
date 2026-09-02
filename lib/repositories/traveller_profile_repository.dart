import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gem.dart';
import '../models/traveller_profile.dart';
import '../models/trip_booking.dart';
import 'gem_repository.dart';

/// The Supabase-aware layer for `traveller_profiles` — mirrors
/// TourRepository/GemRepository's layering.
///
/// [wishlist] and [bookingsHistory] are deliberately NOT columns on
/// `traveller_profiles` — see fetchWishlist/fetchBookingsHistory below for
/// why each is a live query instead. [reviewsWritten] has no query to run
/// at all yet: see fetchReviewsWritten.
class TravellerProfileRepository {
  TravellerProfileRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'traveller_profiles';

  Future<TravellerProfile?> fetchByUserId(String userId) async {
    try {
      final data =
          await _db.from(table).select().eq('user_id', userId).maybeSingle();
      return data == null ? null : TravellerProfile.fromJson(data);
    } catch (e) {
      debugPrint('TravellerProfileRepository.fetchByUserId error: $e');
      return null;
    }
  }

  Future<void> upsert(TravellerProfile profile) async {
    await _db.from(table).upsert(profile.toUpsert());
  }

  /// Wishlist reuses the EXISTING gem-saving mechanism
  /// (`gem_saves`/`GemProvider.toggleSave`/`GemRepository.fetchSavedGems`,
  /// already built and shipping) rather than a second, parallel
  /// saved-items table — confirmed as the right call: a traveller's
  /// "wishlist" and their saved gems are the same real-world concept, and
  /// this app already has exactly one working implementation of "the
  /// places this user bookmarked." This delegates to that repository
  /// directly (RLS scopes it to the signed-in user, same as every other
  /// caller of fetchSavedGems) rather than re-querying `gem_saves` here —
  /// two implementations of the same join would be exactly the drift risk
  /// this reuse decision was meant to avoid. In app UI, prefer
  /// `GemProvider.savedGems` directly (it's already reactive/cached);
  /// this method exists so TravellerProfile's "wishlist" field has one
  /// documented, discoverable answer for where the data actually lives.
  Future<List<Gem>> fetchWishlist(String userId) => GemRepository().fetchSavedGems();

  /// A real, live query against `trip_bookings` — NOT a stored/duplicated
  /// column. "Past & upcoming bookings across all profile types" (the
  /// source schema's own wording) already exists as exactly this data;
  /// this just reads it, the same way TripProvider already does for a
  /// single trip. Two queries (this user's trip ids, then bookings across
  /// those trips) rather than an embedded-filter join — trip_bookings has
  /// no owner column of its own, only `trip_id`, so the owner check has to
  /// go through `trips` regardless; two plain queries are easier to trust
  /// than an unverified PostgREST embedded-filter expression.
  Future<List<TripBooking>> fetchBookingsHistory(String userId) async {
    try {
      final trips =
          await _db.from('trips').select('id').eq('owner_id', userId);
      final tripIds =
          (trips as List).map((t) => (t as Map<String, dynamic>)['id'] as String).toList();
      if (tripIds.isEmpty) return [];
      final data = await _db
          .from('trip_bookings')
          .select()
          .inFilter('trip_id', tripIds)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => TripBooking.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TravellerProfileRepository.fetchBookingsHistory error: $e');
      return [];
    }
  }

  /// Always empty — this app has no reviews/ratings feature anywhere
  /// (Gem Detail has no rating field; Tour explicitly deferred reviews —
  /// see Tour's own doc comment: no real booking backend to legitimately
  /// source them from). Returning an honest empty list rather than
  /// fabricating review data, or building a whole reviews table this phase
  /// was never asked to build, matches this app's established rule against
  /// shipping fields with nothing real behind them.
  Future<List<Never>> fetchReviewsWritten(String userId) async => const [];
}

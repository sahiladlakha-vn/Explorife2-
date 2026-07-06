import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hike.dart';

/// Owns the hike/activity tracking domain only. The expense-splitting state
/// (trip groups and expenses) that used to live here was extracted into
/// `SplitsProvider` so this provider has a single responsibility.
class HikeProvider extends ChangeNotifier {
  static final _db = Supabase.instance.client;

  List<HikeTrack> _hikes = [];
  bool _loading = false;
  String? _error;

  List<HikeTrack> get hikes => _hikes;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> fetchHikes(String userId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _db
          .from('hike_tracks')
          .select()
          .eq('user_id', userId)
          .order('started_at', ascending: false)
          .limit(50);
      _hikes = (data as List).map((e) => HikeTrack.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('fetchHikes error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> logHike({
    required String userId,
    required String title,
    required String activityType,
    double? distanceKm,
    int? durationSeconds,
    double? elevationGainM,
  }) async {
    try {
      await _db.from('hike_tracks').insert({
        'user_id': userId,
        'title': title,
        'activity_type': activityType,
        'distance_km': distanceKm,
        'duration_seconds': durationSeconds,
        'elevation_gain_m': elevationGainM,
        'started_at': DateTime.now().toIso8601String(),
        'featured': false,
      });
      await fetchHikes(userId);
      return true;
    } catch (e) {
      debugPrint('logHike error: $e');
      return false;
    }
  }
}

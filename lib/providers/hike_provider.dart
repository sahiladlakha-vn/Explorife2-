import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hike.dart';

class HikeProvider extends ChangeNotifier {
  static final _db = Supabase.instance.client;

  List<HikeTrack> _hikes = [];
  List<SplitGroup> _groups = [];
  bool _loading = false;
  String? _error;

  List<HikeTrack> get hikes => _hikes;
  List<SplitGroup> get groups => _groups;
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

  Future<void> fetchGroups(String userId) async {
    try {
      // Get groups where user is a member
      final memberData = await _db
          .from('split_group_members')
          .select('group_id')
          .eq('user_id', userId);
      final ids = (memberData as List).map((e) => e['group_id'] as String).toList();
      if (ids.isEmpty) {
        _groups = [];
        notifyListeners();
        return;
      }
      final groupData = await _db
          .from('split_groups')
          .select()
          .inFilter('id', ids)
          .order('created_at', ascending: false);
      _groups = (groupData as List).map((e) => SplitGroup.fromJson(e)).toList();
    } catch (e) {
      debugPrint('fetchGroups error: $e');
    }
    notifyListeners();
  }

  Future<List<SplitExpense>> fetchExpenses(String groupId) async {
    try {
      final data = await _db
          .from('split_expenses')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => SplitExpense.fromJson(e)).toList();
    } catch (e) {
      debugPrint('fetchExpenses error: $e');
      return [];
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

  Future<SplitGroup?> createGroup({
    required String userId,
    required String name,
    String? description,
  }) async {
    try {
      final data = await _db.from('split_groups').insert({
        'name': name,
        'description': description,
        'created_by': userId,
      }).select().single();
      // Add creator as member
      await _db.from('split_group_members').insert({
        'group_id': data['id'],
        'user_id': userId,
      });
      await fetchGroups(userId);
      return SplitGroup.fromJson(data);
    } catch (e) {
      debugPrint('createGroup error: $e');
      return null;
    }
  }

  Future<bool> addExpense({
    required String groupId,
    required String paidBy,
    required String description,
    required double amount,
    String currency = 'USD',
  }) async {
    try {
      await _db.from('split_expenses').insert({
        'group_id': groupId,
        'paid_by': paidBy,
        'description': description,
        'amount': amount,
        'currency': currency,
      });
      return true;
    } catch (e) {
      debugPrint('addExpense error: $e');
      return false;
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gem.dart';

class GemProvider extends ChangeNotifier {
  static final _db = Supabase.instance.client;

  List<Gem> _gems = [];
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  RealtimeChannel? _channel;

  List<Gem> get gems => _filtered;
  List<Gem> get allGems => _gems;
  bool get loading => _loading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;

  List<Gem> get _filtered {
    if (_selectedCategory == 'all') return _gems;
    return _gems.where((g) => g.category == _selectedCategory).toList();
  }

  List<Gem> get mappableGems => _filtered.where((g) => g.hasCoords).toList();

  GemProvider() {
    _fetchGems();
    _subscribeRealtime();
  }

  Future<void> _fetchGems() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _db
          .from('saved_gems')
          .select()
          .order('saved_at', ascending: false)
          .limit(100);
      _gems = (data as List).map((e) => Gem.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('GemProvider fetch error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _subscribeRealtime() {
    _channel = _db
        .channel('public-saved-gems')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'saved_gems',
          callback: (payload) {
            final gem = Gem.fromJson(payload.newRecord);
            _gems = [gem, ..._gems];
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'saved_gems',
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) {
              _gems = _gems.where((g) => g.id != id).toList();
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  void selectCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  Future<Gem?> fetchById(String id) async {
    try {
      final data = await _db
          .from('saved_gems')
          .select()
          .eq('id', id)
          .single();
      return Gem.fromJson(data);
    } catch (e) {
      debugPrint('fetchById error: $e');
      return null;
    }
  }

  Future<List<Gem>> fetchRelated(String category, String excludeId) async {
    try {
      final data = await _db
          .from('saved_gems')
          .select()
          .eq('category', category)
          .neq('id', excludeId)
          .limit(4);
      return (data as List).map((e) => Gem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addGem({
    required String userId,
    required String gemName,
    required String category,
    required double latitude,
    required double longitude,
    String? gemLocation,
    String? description,
    String? difficulty,
    String? bestTimeToVisit,
  }) async {
    try {
      await _db.from('saved_gems').insert({
        'gem_name': gemName,
        'gem_location': gemLocation,
        'category': category,
        'gem_coords': {'lat': latitude, 'lng': longitude},
        'description': description,
        'difficulty': difficulty,
        'best_time_to_visit': bestTimeToVisit,
        'user_id': userId,
      });
      await _fetchGems();
      return true;
    } catch (e) {
      debugPrint('addGem error: $e');
      return false;
    }
  }

  Future<void> refresh() => _fetchGems();

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

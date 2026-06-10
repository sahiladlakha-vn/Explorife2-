import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/story.dart';

class StoryProvider extends ChangeNotifier {
  static final _db = Supabase.instance.client;

  List<Story> _stories = [];
  bool _loading = true;
  String? _error;
  String _activeFilter = 'All';
  RealtimeChannel? _channel;

  List<Story> get stories => _filtered;
  List<Story> get allStories => _stories;
  bool get loading => _loading;
  String? get error => _error;
  String get activeFilter => _activeFilter;

  List<Story> get _filtered {
    if (_activeFilter == 'All') return _stories;
    return _stories.where((s) => s.adventureType == _activeFilter).toList();
  }

  List<Story> get featuredStories => _stories.where((s) => s.featured).toList();

  StoryProvider() {
    _fetch();
    _subscribeRealtime();
  }

  Future<void> _fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _db
          .from('stories')
          .select()
          .eq('status', 'approved')
          .order('featured', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      _stories = (data as List).map((e) => Story.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('StoryProvider fetch error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _subscribeRealtime() {
    _channel = _db
        .channel('public-stories')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stories',
          callback: (_) => _fetch(),
        )
        .subscribe();
  }

  void setFilter(String filter) {
    _activeFilter = filter;
    notifyListeners();
  }

  Future<Story?> fetchById(String id) async {
    try {
      final data = await _db
          .from('stories')
          .select()
          .eq('id', id)
          .eq('status', 'approved')
          .single();
      return Story.fromJson(data);
    } catch (e) {
      debugPrint('fetchById error: $e');
      return null;
    }
  }

  Future<bool> submitStory({
    required String title,
    required String content,
    required String email,
    String? location,
    String? adventureType,
    String? difficulty,
    String? imageUrl,
    int lonelinessLevel = 3,
    String? safetyLevel,
    String? connectivity,
    String? aftermath,
  }) async {
    try {
      await _db.from('stories').insert({
        'title': title,
        'story_content': content,
        'email': email,
        'location': location,
        'adventure_type': adventureType,
        'difficulty': difficulty,
        'image_url': imageUrl,
        'loneliness_level': lonelinessLevel,
        'safety_level': safetyLevel,
        'connectivity': connectivity,
        'aftermath': aftermath,
        'status': 'pending',
        'featured': false,
      });
      return true;
    } catch (e) {
      debugPrint('submitStory error: $e');
      return false;
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

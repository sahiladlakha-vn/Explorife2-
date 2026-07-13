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

  // ── My Stories (owner view) ──────────────────────────────────────────────
  // A dedicated cache, deliberately separate from `_stories`. The public feed
  // (`_stories`) is approved-only — enforced by `_fetch`'s `.eq('status',...)`
  // and by `_applyUpsert` dropping non-approved rows. The owner's own stories
  // must include their PENDING (and rejected) submissions, so mixing them into
  // `_stories` would corrupt the public-feed invariant and let the realtime
  // channel evict them. Keeping a parallel list mirrors GemProvider._savedGems.
  List<Story> _myStories = const [];
  bool _myStoriesLoading = false;
  bool _myStoriesLoaded = false;
  String? _myStoriesError;

  List<Story> get stories => _filtered;
  List<Story> get allStories => _stories;
  bool get loading => _loading;
  String? get error => _error;
  String get activeFilter => _activeFilter;

  List<Story> get myStories => _myStories;
  bool get myStoriesLoading => _myStoriesLoading;
  String? get myStoriesError => _myStoriesError;

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
    // Apply each change as a local delta instead of re-fetching the whole
    // table on every insert/update/delete. A burst of writes used to trigger a
    // burst of full-table reloads; now each event mutates the in-memory list.
    _channel = _db
        .channel('public-stories')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stories',
          callback: (payload) => _applyUpsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'stories',
          callback: (payload) => _applyUpsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'stories',
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id == null) return;
            _stories = _stories.where((s) => s.id != id).toList();
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Insert or update one story in the cache, honouring the same rules the
  /// initial fetch applies: only `approved` stories are kept, and the list
  /// stays sorted (featured first, then newest) to mirror the server ordering.
  /// A story that becomes non-approved is dropped; an approved one is
  /// added/replaced in place.
  void _applyUpsert(Map<String, dynamic> record) {
    final story = Story.fromJson(record);
    final without = _stories.where((s) => s.id != story.id).toList();
    if (story.status != 'approved') {
      _stories = without;
    } else {
      _stories = [...without, story]..sort(_compareStories);
    }
    notifyListeners();
  }

  // Featured stories first, then most-recently created — matches the
  // `order('featured', desc).order('created_at', desc)` server query.
  int _compareStories(Story a, Story b) {
    if (a.featured != b.featured) return a.featured ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
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

  /// Load the signed-in user's own stories by email — INCLUDING pending and
  /// rejected ones. Note the absence of a `.eq('status', ...)` filter: unlike
  /// the public feed, whether a non-approved row is visible here is decided by
  /// RLS on the server, not by the client. If an owner-SELECT policy exists
  /// (e.g. `email = auth.email()`), pending rows come back; if not, RLS
  /// silently filters them and this returns approved-only. Either way the
  /// client asks for everything and renders whatever it's allowed to see.
  ///
  /// Writes ONLY to `_myStories` — never `_stories` — so the public-feed
  /// approved-only invariant and the realtime channel stay untouched.
  Future<void> loadMyStories(String email, {bool force = false}) async {
    if (_myStoriesLoaded && !force) return;
    if (_myStoriesLoading) return;
    _myStoriesLoading = true;
    _myStoriesError = null;
    notifyListeners();
    try {
      final data = await _db
          .from('stories')
          .select()
          .eq('email', email)
          .order('created_at', ascending: false);
      _myStories = (data as List).map((e) => Story.fromJson(e)).toList();
      _myStoriesLoaded = true;
    } catch (e) {
      _myStoriesError = e.toString();
      debugPrint('StoryProvider loadMyStories error: $e');
    } finally {
      _myStoriesLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gem.dart';
import '../models/gem_draft.dart';

/// The **only** Supabase-aware file in the gems domain.
///
/// All Postgres / Storage / Realtime access for gems lives here, behind plain
/// Dart method signatures and [Gem]/[GemDraft] types. State (GemProvider) and
/// UI never import `supabase_flutter`; they call these methods and listen to
/// the [gemInserts] / [gemDeletes] streams. This is the reference
/// implementation of the Presentation → State → Repository → Data layering for
/// the rest of the app to follow.
class GemRepository {
  GemRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Table and Storage bucket names live here as the single source of truth so
  /// nothing else hard-codes the magic strings.
  static const String table = 'saved_gems';
  static const String photosBucket = 'gem-photos';

  RealtimeChannel? _channel;
  final _inserts = StreamController<Gem>.broadcast();
  final _deletes = StreamController<String>.broadcast();

  /// Emits a [Gem] whenever a row is inserted in Postgres (from any client).
  Stream<Gem> get gemInserts => _inserts.stream;

  /// Emits the id of a gem whenever a row is deleted in Postgres.
  Stream<String> get gemDeletes => _deletes.stream;

  // ───────── reads ─────────

  /// Columns plus an optional `profiles` embed for the dropper's display name.
  /// `user_id` carries TWO FKs (one to `auth.users`, one to `public.profiles`),
  /// so the embed is disambiguated by the `saved_gems_profiles_fkey` constraint
  /// name. [fetchGems] still falls back to a plain select if the embed ever
  /// errors (e.g. a stale PostgREST schema cache) — the feed must never break
  /// over a missing handle.
  static const String _selectWithProfile =
      '*, profiles!saved_gems_profiles_fkey(display_name)';

  Future<List<Gem>> fetchGems({int limit = 100}) async {
    try {
      final data = await _db
          .from(table)
          .select(_selectWithProfile)
          .order('saved_at', ascending: false)
          .limit(limit);
      return (data as List).map((e) => Gem.fromJson(e)).toList();
    } catch (e) {
      debugPrint('GemRepository.fetchGems profile embed failed, '
          'falling back to plain select: $e');
      final data = await _db
          .from(table)
          .select()
          .order('saved_at', ascending: false)
          .limit(limit);
      return (data as List).map((e) => Gem.fromJson(e)).toList();
    }
  }

  Future<Gem?> fetchById(String id) async {
    try {
      final data = await _db.from(table).select().eq('id', id).single();
      return Gem.fromJson(data);
    } catch (e) {
      debugPrint('GemRepository.fetchById error: $e');
      return null;
    }
  }

  Future<List<Gem>> fetchRelated(String category, String excludeId) async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('category', category)
          .neq('id', excludeId)
          .limit(4);
      return (data as List).map((e) => Gem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ───────── writes ─────────

  /// Inserts a gem from an approved [draft] and returns the persisted row
  /// (with its DB-assigned id and timestamp). Throws on failure so the caller
  /// can surface a precise error.
  Future<Gem> create(
    GemDraft draft, {
    required String userId,
    List<String> photoUrls = const [],
    Map<String, String> photoCaptions = const {},
  }) async {
    final payload = draft.toGem().toInsert(
          userId: userId,
          lat: draft.lat,
          lng: draft.lng,
        );
    if (photoUrls.isNotEmpty) {
      payload['photo_url'] = photoUrls.first;
      payload['photo_urls'] = photoUrls;
    }
    if (photoCaptions.isNotEmpty) {
      payload['photo_captions'] = photoCaptions;
    }
    final inserted = await _db.from(table).insert(payload).select().single();
    return Gem.fromJson(inserted);
  }

  /// Uploads photos to the public [photosBucket] and returns their public URLs
  /// (in order). Photos that fail are skipped; an empty list means nothing
  /// uploaded. Reads bytes (not a path) so it works on web and native alike.
  Future<List<String>> uploadPhotos(String userId, List<XFile> files) async {
    final urls = <String>[];
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        final dot = f.name.lastIndexOf('.');
        final ext = dot >= 0 ? f.name.substring(dot + 1).toLowerCase() : 'jpg';
        final path =
            '$userId/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
        await _db.storage.from(photosBucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: f.mimeType ?? 'image/jpeg',
                upsert: false,
              ),
            );
        urls.add(_db.storage.from(photosBucket).getPublicUrl(path));
      } catch (e) {
        debugPrint('GemRepository.uploadPhotos error: $e');
      }
    }
    return urls;
  }

  // ───────── saves ─────────

  /// The join table pairing a user with the catalogue gems they've bookmarked.
  /// RLS scopes every read/write to `auth.uid() = user_id`, so no client-side
  /// user filter is needed.
  static const String savesTable = 'gem_saves';

  /// Embeds the full catalogue row for each save so one round-trip yields the
  /// gems themselves, newest-save first. `gem_id` FKs `saved_gems(id)`; the
  /// embed is disambiguated by that constraint. Falls back to a two-query path
  /// if the embed errors (e.g. a stale PostgREST schema cache) so the Saved tab
  /// never breaks over an embed hiccup.
  static const String _savesWithGem =
      'saved_at, saved_gems!gem_saves_gem_id_fkey(*)';

  /// The signed-in user's saved gems, newest save first. Returns `[]` when
  /// signed out (RLS would return nothing anyway).
  Future<List<Gem>> fetchSavedGems() async {
    if (_db.auth.currentUser == null) return [];
    try {
      final data = await _db
          .from(savesTable)
          .select(_savesWithGem)
          .order('saved_at', ascending: false);
      return (data as List)
          .map((e) => e['saved_gems'])
          .whereType<Map<String, dynamic>>()
          .map(Gem.fromJson)
          .toList();
    } catch (e) {
      debugPrint('GemRepository.fetchSavedGems embed failed, '
          'falling back to two queries: $e');
      final ids = await savedGemIds();
      if (ids.isEmpty) return [];
      final data = await _db.from(table).select().inFilter('id', ids.toList());
      return (data as List).map((e) => Gem.fromJson(e)).toList();
    }
  }

  /// The set of gem ids the signed-in user has saved. Used to hydrate the
  /// heart-toggle state; empty when signed out.
  Future<Set<String>> savedGemIds() async {
    if (_db.auth.currentUser == null) return <String>{};
    final data = await _db.from(savesTable).select('gem_id');
    return (data as List).map((e) => e['gem_id'] as String).toSet();
  }

  /// Persists a save. Idempotent: an upsert on the (user_id, gem_id) primary
  /// key means re-saving an already-saved gem is a no-op rather than a
  /// duplicate-key error — critical for cold starts where the in-memory set
  /// hasn't been hydrated yet. Throws when signed out (nothing to attribute).
  Future<void> saveGem(String gemId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('saveGem requires an authenticated user');
    await _db.from(savesTable).upsert(
      {'user_id': uid, 'gem_id': gemId},
      onConflict: 'user_id,gem_id',
      ignoreDuplicates: true,
    );
  }

  /// Removes a save. Already idempotent — deleting a row that isn't there
  /// affects zero rows and does not error.
  Future<void> unsaveGem(String gemId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from(savesTable).delete().eq('user_id', uid).eq('gem_id', gemId);
  }

  // ───────── realtime ─────────

  /// Subscribes to insert/delete changes on the gems table and relays them onto
  /// [gemInserts] / [gemDeletes]. Idempotent — repeated calls are no-ops.
  void connectRealtime() {
    if (_channel != null) return;
    _channel = _db
        .channel('public-saved-gems')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
          callback: (payload) {
            if (!_inserts.isClosed) {
              _inserts.add(Gem.fromJson(payload.newRecord));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: table,
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null && !_deletes.isClosed) _deletes.add(id);
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    await _channel?.unsubscribe();
    _channel = null;
    await _inserts.close();
    await _deletes.close();
  }
}

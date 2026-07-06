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
    String? photoUrl,
  }) async {
    final payload = draft.toGem().toInsert(
          userId: userId,
          lat: draft.lat,
          lng: draft.lng,
        );
    if (photoUrl != null) payload['photo_url'] = photoUrl;
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

  /// Saved-gem ids held in memory for v1. This is a deliberate seam: the bodies
  /// of [saveGem] / [unsaveGem] are local-only today, but the signatures are
  /// the contract the UI/state already code against, so swapping in the
  /// `gem_saves` table later is a one-file change with no caller churn.
  final Set<String> _savedIds = <String>{};

  /// Ids currently marked saved. A defensive copy so callers can't mutate
  /// internal state.
  Set<String> get savedGemIds => Set.unmodifiable(_savedIds);

  /// Marks [gemId] as saved. In-memory for v1; will persist to `gem_saves`.
  Future<void> saveGem(String gemId) async {
    _savedIds.add(gemId);
  }

  /// Removes [gemId] from saved. In-memory for v1; will persist to `gem_saves`.
  Future<void> unsaveGem(String gemId) async {
    _savedIds.remove(gemId);
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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/curated_collection.dart';

/// The **only** Supabase-aware file in the curated-collections domain —
/// mirrors TourRepository's layering. Read-only: there's no creation UI for
/// this content yet, so this has no insert/update methods — content is
/// added directly in Supabase or via collection-sheet-sync.gs.
class CuratedCollectionRepository {
  CuratedCollectionRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'curated_collections';

  Future<List<CuratedCollection>> fetchAll() async {
    try {
      final data =
          await _db.from(table).select().order('sort_order', ascending: true);
      return (data as List)
          .map((e) => CuratedCollection.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CuratedCollectionRepository.fetchAll error: $e');
      return [];
    }
  }
}

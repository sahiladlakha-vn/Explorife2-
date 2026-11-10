import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tour.dart';

/// The **only** Supabase-aware file in the tours domain — mirrors
/// GemRepository's layering (Presentation → State → Repository → Data).
/// Read-only: there's no creation UI for Tour yet, so this has no
/// insert/update methods — content is added directly in Supabase (same
/// entry path as this app's other curated-but-not-yet-authorable content).
class TourRepository {
  TourRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'tours';

  Future<List<Tour>> fetchTours({int limit = 50}) async {
    try {
      // Curated tours always lead (is_curated desc), newest-first within
      // each group — a blank/test row (no photos, no description; created
      // directly in Supabase since there's no authoring UI yet) must never
      // be able to bump a real, fully-written tour out of the front of the
      // Home rail just by having a newer created_at. See Tour.isCurated's
      // own doc comment for the same "never automatic" rule this respects.
      final data = await _db
          .from(table)
          .select()
          .order('is_curated', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => Tour.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TourRepository.fetchTours error: $e');
      return [];
    }
  }

  Future<Tour?> fetchById(String id) async {
    try {
      final data = await _db.from(table).select().eq('id', id).single();
      return Tour.fromJson(data);
    } catch (e) {
      debugPrint('TourRepository.fetchById error: $e');
      return null;
    }
  }
}

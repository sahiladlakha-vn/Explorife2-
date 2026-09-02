import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_action_log_entry.dart';

/// The Supabase-aware layer for `admin_action_log` — the write path for
/// the Admin profile schema's "Action Log" field, and the query path for
/// its "Profiles Approved"/"Disputes Handled" counters (computed by
/// counting this table, not a separately stored/duplicated counter — see
/// the migration's doc comment).
///
/// No caller exists yet anywhere in this app — every admin action the
/// permissions matrix defines depends on the 8 business profile types or a
/// reviews/moderation system, both out of scope this phase. This
/// repository is real, working infrastructure a future phase's admin
/// actions call into, not a stub.
class AdminActionLogRepository {
  AdminActionLogRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'admin_action_log';

  Future<void> logAction({
    required String actorId,
    required AdminActionType actionType,
    String? targetProfileId,
    Map<String, dynamic>? details,
  }) async {
    await _db.from(table).insert({
      'actor_id': actorId,
      'action_type': actionType.wire,
      if (targetProfileId != null) 'target_profile_id': targetProfileId,
      if (details != null) 'details': details,
    });
  }

  Future<List<AdminActionLogEntry>> fetchForActor(String actorId, {int limit = 50}) async {
    try {
      final data = await _db
          .from(table)
          .select()
          .eq('actor_id', actorId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => AdminActionLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AdminActionLogRepository.fetchForActor error: $e');
      return [];
    }
  }

  /// Backs "Profiles Approved" (pass `{AdminActionType.approveListing}`)
  /// and "Disputes Handled" (pass whichever action types count as a
  /// dispute resolution once that concept exists) — a live count, not a
  /// stored counter, so it can never drift from the log it summarizes.
  Future<int> countActions(String actorId, Set<AdminActionType> types) async {
    try {
      final data = await _db
          .from(table)
          .select('id')
          .eq('actor_id', actorId)
          .inFilter('action_type', types.map((t) => t.wire).toList());
      return (data as List).length;
    } catch (e) {
      debugPrint('AdminActionLogRepository.countActions error: $e');
      return 0;
    }
  }
}

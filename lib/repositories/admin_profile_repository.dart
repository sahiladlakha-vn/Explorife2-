import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_profile.dart';

/// The Supabase-aware layer for `admin_profiles` — mirrors
/// TourRepository/GemRepository's layering.
class AdminProfileRepository {
  AdminProfileRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String table = 'admin_profiles';

  Future<AdminProfile?> fetchByUserId(String userId) async {
    try {
      final data =
          await _db.from(table).select().eq('user_id', userId).maybeSingle();
      return data == null ? null : AdminProfile.fromJson(data);
    } catch (e) {
      debugPrint('AdminProfileRepository.fetchByUserId error: $e');
      return null;
    }
  }

  Future<void> upsert(AdminProfile profile) async {
    await _db.from(table).upsert(profile.toInsert());
  }

  /// Called from AuthProvider right after a successful admin sign-in.
  /// [ip] is client-reported (this app has no server-side request capture
  /// to source a trusted IP from — a Flutter client has no way to know its
  /// own public IP without asking an external lookup service; that's the
  /// honest limit of "system-logged" here, not a fake stand-in for a real
  /// server-side audit capture).
  Future<void> recordLogin(String userId, {String? ip}) async {
    try {
      await _db.from(table).update({
        'last_login': DateTime.now().toIso8601String(),
        if (ip != null) 'last_login_ip': ip,
      }).eq('user_id', userId);
    } catch (e) {
      debugPrint('AdminProfileRepository.recordLogin error: $e');
    }
  }
}

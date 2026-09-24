import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/role.dart';

/// Thrown by [AdminUserRepository.updateRole] with just the server's own
/// message (insufficient privilege, target is a guest session, last-
/// super_admin guard, ...) — `admin_update_user_role` raises a real
/// Postgres exception for all of these rather than silently affecting 0
/// rows, so the caller gets something more useful than a bare
/// [PostgrestException] to show in a snackbar.
class AdminRoleUpdateException implements Exception {
  final String message;
  AdminRoleUpdateException(this.message);
  @override
  String toString() => message;
}

/// One row of the admin "Users" roster — see [AdminUserRepository] for
/// where this data actually comes from and why.
class AdminUserRow {
  final String id;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? email;
  final String? provider;
  final bool isAnonymous;
  final Role role;
  final DateTime createdAt;
  final int tripCount;

  AdminUserRow({
    required this.id,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.email,
    required this.provider,
    required this.isAnonymous,
    required this.role,
    required this.createdAt,
    required this.tripCount,
  });

  factory AdminUserRow.fromJson(Map<String, dynamic> json) => AdminUserRow(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        email: json['email'] as String?,
        provider: json['provider'] as String?,
        isAnonymous: json['is_anonymous'] as bool? ?? false,
        role: Role.fromWire(json['role'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String),
        tripCount: (json['trip_count'] as num?)?.toInt() ?? 0,
      );
}

/// One page of [AdminUserRow]s plus the total row count across all pages
/// (needed for "Page X of Y" — the RPC returns it as a window-function
/// column on every row rather than a second round trip).
class AdminUserPage {
  final List<AdminUserRow> users;
  final int total;
  const AdminUserPage({required this.users, required this.total});
  static const empty = AdminUserPage(users: [], total: 0);
}

/// Backs the desktop Settings screen's admin-only "Users" panel.
///
/// Deliberately calls the `admin_list_users` Postgres function (SECURITY
/// DEFINER) instead of a plain `.from('profiles').select(...)` — that
/// table already carries permissive `qual: true` SELECT policies for
/// anon/authenticated/public (relied on elsewhere, e.g. resolving
/// shared-trip co-travelers' names/avatars), so a client-side role check
/// alone would just be hiding a UI element in front of data anyone could
/// already fetch directly. The function re-checks the caller's role
/// itself and returns zero rows for a non-admin — including a non-admin
/// who calls this RPC directly, bypassing the Settings UI entirely. See
/// the `admin_list_users_function` migration for the exact role check and
/// the reasoning for returning empty rather than raising.
class AdminUserRepository {
  AdminUserRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<AdminUserPage> fetchUsers({
    String? search,
    required int page,
    int pageSize = 20,
    // Off by default — matches the "Users" panel's curated view (real
    // accounts only). The "Profiles" panel passes true for the raw,
    // unfiltered view of every `profiles` row, guest sessions included.
    bool includeAnonymous = false,
  }) async {
    final trimmed = search?.trim();
    final data = await _db.rpc('admin_list_users', params: {
      'p_search': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'p_limit': pageSize,
      'p_offset': page * pageSize,
      'p_include_anonymous': includeAnonymous,
    });
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return AdminUserPage.empty;
    final total = (rows.first['total_count'] as num).toInt();
    return AdminUserPage(
      users: rows.map(AdminUserRow.fromJson).toList(),
      total: total,
    );
  }

  /// Changes another account's role. Only a `super_admin` may call this
  /// successfully — the `admin_update_user_role` function re-checks that
  /// server-side via `is_super_admin()` regardless of who's calling it
  /// (same defense-in-depth reasoning as [fetchUsers]'s doc comment), and
  /// also rejects assigning a role to an anonymous/guest row or demoting
  /// the last remaining super_admin. Goes through that dedicated RPC
  /// rather than a plain `.from('profiles').update(...)` specifically so a
  /// disallowed attempt raises (caught below) instead of just updating 0
  /// rows and returning success.
  Future<void> updateRole({
    required String userId,
    required Role newRole,
  }) async {
    try {
      await _db.rpc('admin_update_user_role', params: {
        'p_target_id': userId,
        'p_new_role': newRole.wire,
      });
    } on PostgrestException catch (e) {
      throw AdminRoleUpdateException(e.message);
    }
  }
}

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

/// Thrown by [AdminUserRepository.createUser] and
/// [AdminUserRepository.resendInvite] — both go through the `admin-create-
/// user` Edge Function (see that function's own doc comment for why this
/// can't just be a plain RPC: it needs the service-role key for the Auth
/// Admin API, which must never reach the client). The function always
/// responds with a JSON `{"error": "..."}` body on a non-2xx status, so this
/// carries that message straight through rather than a generic
/// [FunctionException] with an opaque status code.
class AdminUserActionException implements Exception {
  final String message;
  AdminUserActionException(this.message);
  @override
  String toString() => message;

  static AdminUserActionException from(FunctionException e, String fallback) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      return AdminUserActionException(details['error'] as String);
    }
    return AdminUserActionException(fallback);
  }
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
  // From auth.users, added by the `admin_list_users_invite_status`
  // migration. A row is a "Pending invite" iff it was invited AND has never
  // confirmed its email — the same two columns `admin_create_user_profile`
  // itself gates on server-side, so this client-side label can't drift from
  // what the Edge Function/RPC actually treat as "still pending".
  final DateTime? invitedAt;
  final DateTime? emailConfirmedAt;

  bool get isPendingInvite => invitedAt != null && emailConfirmedAt == null;

  // Backs the Users panel's optimistic post-reassignment update (see
  // _UsersPanelState._reassign) — lets the row's role badge flip the
  // instant admin_update_user_role succeeds, without a full re-fetch (and
  // the loading-spinner flash that replaces the whole table while it's in
  // flight; see _UsersPanelState.build's `if (_loading)` branch).
  AdminUserRow copyWith({Role? role}) => AdminUserRow(
        id: id,
        displayName: displayName,
        username: username,
        avatarUrl: avatarUrl,
        email: email,
        provider: provider,
        isAnonymous: isAnonymous,
        role: role ?? this.role,
        createdAt: createdAt,
        tripCount: tripCount,
        invitedAt: invitedAt,
        emailConfirmedAt: emailConfirmedAt,
      );

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
    this.invitedAt,
    this.emailConfirmedAt,
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
        invitedAt: json['invited_at'] == null
            ? null
            : DateTime.parse(json['invited_at'] as String),
        emailConfirmedAt: json['email_confirmed_at'] == null
            ? null
            : DateTime.parse(json['email_confirmed_at'] as String),
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

/// One row of `admin_role_counts()` — how many real (non-anonymous)
/// accounts currently hold each [Role]. Always has exactly 7 entries, one
/// per [Role] value, even at 0 users — see that function's doc comment
/// for why (the admin Profiles list shows every role, Salesforce-style,
/// not just the ones with members today).
class AdminRoleCount {
  final Role role;
  final int userCount;
  const AdminRoleCount({required this.role, required this.userCount});

  factory AdminRoleCount.fromJson(Map<String, dynamic> json) =>
      AdminRoleCount(
        role: Role.fromWire(json['role'] as String?),
        userCount: (json['user_count'] as num?)?.toInt() ?? 0,
      );
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
    // accounts only). The Users tab's "All accounts" view passes true for
    // the raw, unfiltered view of every `profiles` row, guest sessions
    // included.
    bool includeAnonymous = false,
    // Set by the Profiles detail page's "Assigned Users" section to scope
    // the roster to one role — null (the default) matches every role,
    // same as every pre-existing call site.
    Role? role,
  }) async {
    final trimmed = search?.trim();
    final data = await _db.rpc('admin_list_users', params: {
      'p_search': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'p_limit': pageSize,
      'p_offset': page * pageSize,
      'p_include_anonymous': includeAnonymous,
      if (role != null) 'p_role': role.wire,
    });
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return AdminUserPage.empty;
    final total = (rows.first['total_count'] as num).toInt();
    return AdminUserPage(
      users: rows.map(AdminUserRow.fromJson).toList(),
      total: total,
    );
  }

  /// Backs the admin Profiles list's "Users" column — one row per [Role],
  /// always all 7 even at 0 members. See `admin_role_counts()`'s doc
  /// comment for the admin-gate/anonymous-exclusion behavior (same
  /// conventions as [fetchUsers]'s default view).
  Future<List<AdminRoleCount>> fetchRoleCounts() async {
    final data = await _db.rpc('admin_role_counts');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(AdminRoleCount.fromJson)
        .toList();
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

  /// Backs the Users panel's "New User" form. Goes through the
  /// `admin-create-user` Edge Function rather than any client-side call —
  /// sending the invite email requires the service-role key
  /// (`auth.admin.inviteUserByEmail`), which must never reach the client;
  /// see that function's own doc comment for the full two-client design.
  /// The function itself re-checks super_admin server-side, so this is
  /// exactly as safe to call as [updateRole] is — a non-admin caller just
  /// gets [AdminUserActionException] back instead of anything happening.
  Future<AdminUserRow> createUser({
    required String fullName,
    required String email,
    String? username,
    required Role role,
  }) async {
    try {
      final response = await _db.functions.invoke('admin-create-user', body: {
        'full_name': fullName,
        'email': email,
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
        'role': role.wire,
      });
      final data = response.data as Map<String, dynamic>;
      return AdminUserRow.fromJson(data['user'] as Map<String, dynamic>);
    } on FunctionException catch (e) {
      throw AdminUserActionException.from(e, 'Could not create the user.');
    }
  }

  /// Backs the Users panel's row-level "Resend invite" action, shown only
  /// for a row where [AdminUserRow.isPendingInvite] is true. Deliberately
  /// sends only the target's id — the Edge Function looks up the email
  /// server-side via the service-role Auth Admin API rather than trusting
  /// one from the client, and independently re-confirms the invite is still
  /// pending before resending (see that function's `handleResendInvite`).
  Future<void> resendInvite(String userId) async {
    try {
      await _db.functions.invoke('admin-create-user', body: {
        'action': 'resend_invite',
        'user_id': userId,
      });
    } on FunctionException catch (e) {
      throw AdminUserActionException.from(e, 'Could not resend the invite.');
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/role.dart';
import '../repositories/admin_profile_repository.dart';

class AuthUser {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? provider;
  final String? username;

  /// Defaults to [Role.traveler] until the real `profiles.role` value
  /// loads — every account has exactly one role (see role.dart), so this
  /// default only ever reflects "not loaded yet," never a genuinely
  /// roleless account.
  final Role role;

  const AuthUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.provider,
    this.username,
    this.role = Role.traveler,
  });
}

/// Another user's public identity, as resolved by [AuthProvider.findUserByIdentifier].
/// Distinct from [AuthUser] (the signed-in account) — this is read-only, never
/// the current session's own state.
class PublicProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? username;

  const PublicProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.username,
  });
}

class AuthProvider extends ChangeNotifier {
  AuthUser? _user;
  bool _loading = true;
  StreamSubscription<AuthState>? _authSubscription;

  AuthUser? get user => _user;
  bool get loading => _loading;
  bool get isAuthenticated => _user != null;
  Role get role => _user?.role ?? Role.traveler;

  static final _supabase = Supabase.instance.client;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Safety timeout — never stay stuck loading
    Future.delayed(const Duration(seconds: 3), () {
      if (_loading) {
        _loading = false;
        notifyListeners();
      }
    });

    try {
      final session = _supabase.auth.currentSession;
      if (session?.user != null) {
        _user = await _loadProfile(session!.user);
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }

    // Listen for auth state changes (login, logout, token refresh)
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      final wasSignedIn = _user != null;
      if (session?.user == null) {
        _user = null;
      } else {
        try {
          _user = await _loadProfile(session!.user);
        } catch (_) {
          _user = _quickUser(session!.user);
        }
        // Real sign-in transition (not a token refresh on an already-loaded
        // session) for an admin-tier account — record it. Never blocks or
        // fails sign-in itself; see recordLastLoginIfAdmin's own doc.
        if (!wasSignedIn && _user != null && _user!.role.isAdminTier) {
          unawaited(_recordLastLoginIfAdmin(_user!.id));
        }
      }
      _loading = false;
      notifyListeners();
    });
  }

  Future<AuthUser> _loadProfile(User authUser) async {
    final data = await _supabase
        .from('profiles')
        .select('display_name, avatar_url, username, role')
        .eq('id', authUser.id)
        .maybeSingle();

    final meta = authUser.userMetadata ?? {};
    final fallbackName = (meta['full_name'] as String?) ??
        (meta['name'] as String?) ??
        authUser.email?.split('@').first ??
        'Explorer';

    return AuthUser(
      id: authUser.id,
      email: authUser.email,
      name: (data?['display_name'] as String?) ?? fallbackName,
      avatarUrl: (data?['avatar_url'] as String?) ??
          (meta['avatar_url'] as String?) ??
          (meta['picture'] as String?),
      provider: authUser.appMetadata['provider'] as String?,
      username: data?['username'] as String?,
      role: Role.fromWire(data?['role'] as String?),
    );
  }

  AuthUser _quickUser(User authUser) {
    final meta = authUser.userMetadata ?? {};
    return AuthUser(
      id: authUser.id,
      email: authUser.email,
      name: (meta['full_name'] as String?) ??
          (meta['name'] as String?) ??
          authUser.email?.split('@').first ??
          'Explorer',
      avatarUrl: (meta['avatar_url'] as String?) ?? (meta['picture'] as String?),
      provider: authUser.appMetadata['provider'] as String?,
      // role deliberately left at its Role.traveler default here — this is
      // the "profiles row failed to load" fallback path, and defaulting an
      // admin account to the LEAST-privileged role on a load failure is the
      // safe direction to fail in, not a real signal about the account.
    );
  }

  /// Best-effort "Last Login"/"Last Login IP" update for admin_profiles —
  /// see AdminProfileRepository.recordLogin's own doc comment for why the
  /// IP is client-reported (a Flutter client has no other way to learn its
  /// own public IP) rather than server-verified. Swallows all errors: this
  /// is an audit nicety, never something that should block or fail a
  /// sign-in.
  Future<void> _recordLastLoginIfAdmin(String userId) async {
    String? ip;
    try {
      final res = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) ip = res.body.trim();
    } catch (_) {
      // No IP this time — last_login itself still gets recorded below.
    }
    await AdminProfileRepository().recordLogin(userId, ip: ip);
  }

  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.explorife.app://login-callback',
    );
  }

  Future<void> signInWithGitHub() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: kIsWeb ? null : 'io.explorife.app://login-callback',
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    if (_user == null) return;
    await _supabase
        .from('profiles')
        .update({'display_name': name})
        .eq('id', _user!.id);
    _user = AuthUser(
      id: _user!.id,
      name: name,
      email: _user!.email,
      avatarUrl: _user!.avatarUrl,
      provider: _user!.provider,
      username: _user!.username,
      role: _user!.role,
    );
    notifyListeners();
  }

  /// Throws [PostgrestException] on a taken/invalid username (unique index /
  /// format CHECK on profiles.username) — callers should catch and surface a
  /// friendly message rather than letting it bubble as a generic error.
  Future<void> updateUsername(String username) async {
    if (_user == null) return;
    final normalized = username.trim().toLowerCase();
    await _supabase
        .from('profiles')
        .update({'username': normalized})
        .eq('id', _user!.id);
    _user = AuthUser(
      id: _user!.id,
      name: _user!.name,
      email: _user!.email,
      avatarUrl: _user!.avatarUrl,
      provider: _user!.provider,
      username: normalized,
      role: _user!.role,
    );
    notifyListeners();
  }

  /// Resolves an email or username to the account it belongs to, via the
  /// find_user_by_identifier RPC (security definer — clients can't otherwise
  /// read auth.users for the email side). Exact match only; null when nothing
  /// matches. Backs the traveler-invite search (trip-setup wizard + Trip
  /// tab's "+ Add Traveler").
  Future<PublicProfile?> findUserByIdentifier(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    final rows = await _supabase
        .rpc('find_user_by_identifier', params: {'p_identifier': trimmed}) as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final displayName = row['display_name'] as String?;
    return PublicProfile(
      id: row['id'] as String,
      displayName: (displayName == null || displayName.trim().isEmpty)
          ? 'Explorer'
          : displayName,
      avatarUrl: row['avatar_url'] as String?,
      username: row['username'] as String?,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

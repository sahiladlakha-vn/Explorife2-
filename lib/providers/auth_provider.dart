import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? provider;
  final String? username;

  const AuthUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.provider,
    this.username,
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
      if (session?.user == null) {
        _user = null;
      } else {
        try {
          _user = await _loadProfile(session!.user);
        } catch (_) {
          _user = _quickUser(session!.user);
        }
      }
      _loading = false;
      notifyListeners();
    });
  }

  Future<AuthUser> _loadProfile(User authUser) async {
    final data = await _supabase
        .from('profiles')
        .select('display_name, avatar_url, username')
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
    );
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

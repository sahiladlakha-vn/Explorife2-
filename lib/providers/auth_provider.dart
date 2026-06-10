import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? provider;

  const AuthUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.provider,
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
        .select('display_name, avatar_url')
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
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

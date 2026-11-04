import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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

  /// True for a Supabase anonymous session (see [AuthProvider.signInAsGuest]).
  /// Drives the "Guest" label/badge in the Profile header — a guest is a
  /// real authenticated user (RLS-visible, `auth.uid()` non-null), just one
  /// with no real-world identity behind it yet.
  final bool isGuest;

  const AuthUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.provider,
    this.username,
    this.role = Role.traveler,
    this.isGuest = false,
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
      var session = _supabase.auth.currentSession;
      if (session?.user == null) {
        // No session at all (fresh install, cleared storage, first-ever
        // launch) — the app never shows a forced sign-in gate anymore, so
        // create a real anonymous session automatically rather than
        // leaving every screen to fend for a null auth.uid(). This is the
        // SAME mechanism signInAsGuest() below already used for the old
        // "Skip for now" button; the only change is that it now fires on
        // its own instead of waiting for a tap.
        await _supabase.auth.signInAnonymously();
        session = _supabase.auth.currentSession;
      }
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
    // Anonymous sessions carry no metadata/email to derive a name from —
    // "Guest" beats the generic "Explorer" fallback at signalling that this
    // is a skipped-auth session, not a real (if unnamed) account.
    final fallbackName = authUser.isAnonymous
        ? 'Guest'
        : (meta['full_name'] as String?) ??
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
      isGuest: authUser.isAnonymous,
    );
  }

  AuthUser _quickUser(User authUser) {
    final meta = authUser.userMetadata ?? {};
    return AuthUser(
      id: authUser.id,
      email: authUser.email,
      name: authUser.isAnonymous
          ? 'Guest'
          : (meta['full_name'] as String?) ??
              (meta['name'] as String?) ??
              authUser.email?.split('@').first ??
              'Explorer',
      avatarUrl:
          (meta['avatar_url'] as String?) ?? (meta['picture'] as String?),
      provider: authUser.appMetadata['provider'] as String?,
      isGuest: authUser.isAnonymous,
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
      if (res.statusCode == 200 && res.body.trim().isNotEmpty)
        ip = res.body.trim();
    } catch (_) {
      // No IP this time — last_login itself still gets recorded below.
    }
    await AdminProfileRepository().recordLogin(userId, ip: ip);
  }

  /// Web's OAuth redirect target — explicitly the app's own `/auth/callback`
  /// route (under the hash, since this app uses Flutter web's default hash
  /// URL strategy), NOT null/omitted. Leaving `redirectTo` null used to
  /// mean "fall back to the Supabase project's bare Site URL"
  /// (`https://explorife2.vercel.app`, no `#/auth/callback`) — fine on a
  /// SUCCESSFUL sign-in, since supabase_flutter's own session-detection
  /// strips a success token out of the URL before GoRouter ever sees it as
  /// a "location" to match. On a FAILED sign-in (e.g. `identity_already_
  /// exists` when the Google account picked is already linked to a
  /// different, older real account — a real, expected case now that guest
  /// upgrades exist, not just a test artifact), GoTrue appends
  /// `?error=...&error_code=...` to that same bare origin instead, nothing
  /// strips it, and GoRouter crashes with "no routes for location" trying
  /// to match the raw query string as a path. Pointing this at a real,
  /// registered route fixes both cases the same way — _AuthCallbackScreen
  /// below now branches on whether `error` is present.
  static String? get _webRedirectTo =>
      kIsWeb ? '${Uri.base.origin}/#/auth/callback' : null;

  /// Signs in with Google — LINKING to the current anonymous session
  /// in-place (same `auth.uid()`, `is_anonymous` flips to false) when the
  /// signed-in user is still a guest, so nothing they saved/created before
  /// this point (a saved gem, a trip draft, ...) gets orphaned under an id
  /// nobody can reach anymore. Falls back to a plain sign-in only when
  /// there's no session to link from at all — shouldn't happen in normal
  /// use now that [signInAsGuest]'s mechanism runs automatically on cold
  /// start (see _init), but this stays correct if it somehow does.
  ///
  /// The link flow is a full-page redirect on web (same mechanism
  /// supabase_flutter's own signInWithOAuth uses internally — see
  /// GoTrueClientSignInProvider.signInWithOAuth), NOT a same-tab popup, so
  /// any in-memory "resume this after sign-in" state would be lost; callers
  /// that need to resume a specific action use requireAccount/PendingAction
  /// (sign_in_sheet.dart) to persist that across the redirect instead.
  Future<void> signInWithGoogle() async {
    if (_user?.isGuest ?? false) {
      final res = await _supabase.auth.getLinkIdentityUrl(
        OAuthProvider.google,
        redirectTo: _webRedirectTo ?? 'io.explorife.app://login-callback',
      );
      await launchUrl(Uri.parse(res.url), webOnlyWindowName: '_self');
      return;
    }
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _webRedirectTo ?? 'io.explorife.app://login-callback',
    );
  }

  /// Always a plain (non-linking) Google sign-in, regardless of the current
  /// session's guest state — the recovery action for the `identity_already_
  /// exists` error screen (app_router.dart). [signInWithGoogle]'s link
  /// attempt is exactly what fails when the picked Google identity already
  /// belongs to a different, older real account; this bypasses linking
  /// entirely and just signs the browser into whatever account that
  /// identity already owns, same as visiting /auth fresh would. Replaces
  /// the current anonymous session outright — any guest-only data isn't
  /// preserved, same tradeoff as any other "sign into an existing account"
  /// transition.
  Future<void> signInWithGoogleDirect() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _webRedirectTo ?? 'io.explorife.app://login-callback',
    );
  }

  Future<void> signInWithGitHub() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: _webRedirectTo ?? 'io.explorife.app://login-callback',
    );
  }

  /// A real (anonymous) Supabase session — `auth.uid()` non-null, owner-
  /// scoped RLS policies (`user_id = auth.uid()`) satisfied like any other
  /// signed-in user. Called automatically from [_init] on cold start now
  /// (there's no forced sign-in gate left to opt into this from), so
  /// callers don't normally need to invoke this directly anymore; kept
  /// public in case a screen ever needs to force a fresh guest session
  /// explicitly (e.g. after sign-out). Requires "Allow anonymous sign-ins"
  /// to be enabled in the Supabase project's Auth settings — this call
  /// throws (surfaced by the caller's existing error handling) if it isn't.
  Future<void> signInAsGuest() async {
    await _supabase.auth.signInAnonymously();
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
        .update({'display_name': name}).eq('id', _user!.id);
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
        .update({'username': normalized}).eq('id', _user!.id);
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
    final rows = await _supabase.rpc('find_user_by_identifier',
        params: {'p_identifier': trimmed}) as List;
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

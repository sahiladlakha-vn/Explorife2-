import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;
import '../../core/services/pending_action.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'oauth_button.dart';

/// Gate for any write action that should require a real (non-guest)
/// account. Call this at the TOP of the action's handler:
///
/// ```dart
/// Future<void> _save() async {
///   if (!await requireAccount(context, action: 'save_gem', payload: {'gemId': gem.id})) {
///     return; // sheet is showing; the actual save happens after sign-in instead
///   }
///   await context.read<GemProvider>().toggleSave(gem);
/// }
/// ```
///
/// Returns `true` immediately if the current user already has a real
/// account — the caller proceeds with the write right away, no sheet shown.
/// Returns `false` after showing [SignInSheet] — [payload] is persisted
/// first (see [PendingAction]) so `_AuthCallbackScreen` (app_router.dart)
/// can re-run the equivalent action once sign-in actually completes; a
/// full-page OAuth redirect on web tears down the running app, so nothing
/// held only in memory (like a bare callback closure) would survive it.
Future<bool> requireAccount(
  BuildContext context, {
  required String action,
  Map<String, dynamic> payload = const {},
  String reason = 'Sign in to save your progress and pick up where you left off.',
}) async {
  final auth = context.read<AuthProvider>();
  if (auth.isAuthenticated && !(auth.user?.isGuest ?? true)) return true;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        SignInSheet(reason: reason, action: action, payload: payload),
  );
  return false;
}

/// The contextual sign-in prompt itself — a bottom sheet, never a full-
/// screen takeover (that was the old, now-removed forced onboarding/auth
/// gate's shape). Content mirrors AuthScreen's Google button, just smaller.
class SignInSheet extends StatefulWidget {
  const SignInSheet({
    super.key,
    required this.reason,
    required this.action,
    required this.payload,
  });

  final String reason;
  final String action;
  final Map<String, dynamic> payload;

  @override
  State<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<SignInSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Persisted BEFORE the redirect fires — signInWithGoogle() navigates
      // the whole page away on web, so this has to survive on disk, not in
      // memory. See PendingAction's own doc comment.
      await PendingAction.save(
          PendingAction(type: widget.action, payload: widget.payload));
      await context.read<AuthProvider>().signInWithGoogle();
      // No further UI update expected past this point on web — the page
      // navigates away. Native's deep-link return keeps this widget alive,
      // hence the mounted guard below rather than assuming teardown.
    } catch (e) {
      await PendingAction.takeAndClear(); // don't leave a stale action queued
      // 'manual_linking_disabled' means the Supabase project's Auth
      // settings haven't turned on "Allow manual linking" yet — a required
      // one-time dashboard toggle for guest→real upgrades to preserve the
      // same auth.uid() (same category of manual step as "Allow anonymous
      // sign-ins" already was). Worth a clearer message than the raw
      // exception text, since it's a real, fixable setup gap, not a
      // transient failure.
      final message = (e is AuthApiException && e.code == 'manual_linking_disabled')
          ? 'Sign-in isn\'t fully set up yet. Please try again shortly.'
          : e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: AppTheme.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Sign in to continue',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 24, color: AppTheme.lightInk)),
                const SizedBox(height: 8),
                Text(
                  widget.reason,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fredoka(
                      fontSize: 13, color: AppTheme.lightMute, height: 1.4),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    ),
                    child: Text(_error!,
                        style:
                            GoogleFonts.fredoka(color: Colors.red, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                OAuthButton(
                  label: 'Continue with Google',
                  icon: googleIcon,
                  loading: _loading,
                  onTap: _continueWithGoogle,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: Text('Not now',
                      style: GoogleFonts.fredoka(
                          fontSize: 13, color: AppTheme.lightMute)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

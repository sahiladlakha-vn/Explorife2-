import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/oauth_button.dart';

/// Full-page sign-in — reached only voluntarily now (e.g. a "Sign in" link
/// in Profile), never as a forced gate: every session starts as a real
/// (anonymous) guest automatically (see AuthProvider._init), so there's
/// nothing to "skip" anymore. [redirectTo] still lets a caller land back
/// on a specific route after sign-in completes, same as before.
class AuthScreen extends StatefulWidget {
  final String? redirectTo;
  const AuthScreen({super.key, this.redirectTo});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn(Future<void> Function() method) async {
    setState(() { _loading = true; _error = null; });
    try {
      await method();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.network(
            'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=800&q=80',
            fit: BoxFit.cover,
          ),
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  AppTheme.bg.withValues(alpha: 0.95),
                  AppTheme.bg,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(),
                  // Brand
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Explor', style: GoogleFonts.audiowide(fontSize: 32, color: Colors.white)),
                      Text('ife', style: GoogleFonts.audiowide(fontSize: 32, color: AppTheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'THE LIFE YOU WERE\nMEANT TO EXPLORE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.bebasNeue(fontSize: 28, color: Colors.white, height: 1.1, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to save your gems, plan trips, and pick up\nright where you left off on any device',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fredoka(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 40),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Text(_error!, style: GoogleFonts.fredoka(color: Colors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Google button — AuthProvider.signInWithGoogle links this
                  // to the existing guest session (same auth.uid()) rather
                  // than starting a brand new one, so nothing the guest
                  // already saved/created is orphaned.
                  OAuthButton(
                    label: 'Continue with Google',
                    icon: googleIcon,
                    loading: _loading,
                    onTap: () => _signIn(context.read<AuthProvider>().signInWithGoogle),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'By continuing you agree to our Terms of Service\nand Privacy Policy',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fredoka(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

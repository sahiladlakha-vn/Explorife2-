import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

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
                  Colors.black.withOpacity(0.3),
                  AppTheme.bg.withOpacity(0.95),
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
                    'Join 84,000+ adventurers discovering\nhidden trails around the world',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 40),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(_error!, style: GoogleFonts.dmSans(color: Colors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Google button
                  _OAuthButton(
                    label: 'Continue with Google',
                    icon: _googleIcon,
                    loading: _loading,
                    onTap: () => _signIn(context.read<AuthProvider>().signInWithGoogle),
                  ),
                  const SizedBox(height: 12),

                  // GitHub button
                  _OAuthButton(
                    label: 'Continue with GitHub',
                    icon: _githubIcon,
                    loading: _loading,
                    dark: true,
                    onTap: () => _signIn(context.read<AuthProvider>().signInWithGitHub),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'By continuing you agree to our Terms of Service\nand Privacy Policy',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _OAuthButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool loading;
  final bool dark;

  const _OAuthButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF24292E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark ? const Color(0xFF444D56) : Colors.white),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Google SVG icon
Widget get _googleIcon => SizedBox(
      width: 20, height: 20,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    // Simplified Google G
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: Offset(c, c), radius: c), -1.57, 3.14, false, paint..style = PaintingStyle.stroke..strokeWidth = size.width * 0.2);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: Offset(c, c), radius: c), 1.57, 1.57, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: Offset(c, c), radius: c), -1.57, -1.57, false, paint);
  }
  @override
  bool shouldRepaint(_) => false;
}

// GitHub icon
Widget get _githubIcon => const Icon(Icons.code, color: Colors.white, size: 20);

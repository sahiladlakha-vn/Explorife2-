import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      emoji: '🧗',
      title: 'DISCOVER\nHIDDEN GEMS',
      body: 'Find secret trails, waterfalls, and viewpoints shared by real adventurers — not tourist guides.',
    ),
    _OnboardPage(
      emoji: '🗺️',
      title: 'MAP YOUR\nADVENTURES',
      body: 'Track every hike, log your route, and build a personal atlas of everywhere you\'ve been.',
    ),
    _OnboardPage(
      emoji: '📖',
      title: 'SHARE YOUR\nSTORY',
      body: 'Write field dispatches, split costs with your crew, and inspire the next generation of explorers.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Skip onboarding if already authenticated
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/home'));
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _pages.length,
            itemBuilder: (_, i) => _pages[i],
          ),

          // Bottom controls
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppTheme.bg.withOpacity(0.98)],
                ),
              ),
              child: Column(children: [
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppTheme.primary : AppTheme.surface2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _page == _pages.length - 1 ? 'GET STARTED →' : 'NEXT →',
                      style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/auth'),
                  child: Text('Skip',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final String emoji, title, body;
  const _OnboardPage({required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 200),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 24),
          Text(title,
              style: GoogleFonts.bebasNeue(
                  fontSize: 48, color: AppTheme.textPrimary,
                  letterSpacing: 0.5, height: 1.0)),
          const SizedBox(height: 16),
          Text(body,
              style: GoogleFonts.dmSans(
                  fontSize: 16, color: AppTheme.textSecondary, height: 1.7)),
        ],
      ),
    );
  }
}

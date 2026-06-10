import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/auth_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/explore/explore_screen.dart';
import '../../screens/listings/listings_screen.dart';
import '../../screens/listings/destination_detail_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/gems/gem_detail_screen.dart';
import '../../screens/gems/add_gem_screen.dart';
import '../../screens/stories/stories_screen.dart';
import '../../screens/stories/story_detail_screen.dart';
import '../../screens/stories/submit_story_screen.dart';
import '../../screens/hikes/hikes_screen.dart';
import '../../screens/hikes/log_hike_screen.dart';
import '../../screens/splits/splits_screen.dart';
import '../../screens/splits/split_detail_screen.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../widgets/common/app_shell.dart';

const _protectedRoutes = {'/profile', '/drop-gem', '/submit-story', '/log-hike', '/splits'};

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/onboarding',
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final path = state.uri.path;
      final isProtected = _protectedRoutes.any((r) => path.startsWith(r));

      if (auth.loading) return null;
      // Skip onboarding if already authenticated
      if (path == '/onboarding' && auth.isAuthenticated) return '/home';
      if (isProtected && !auth.isAuthenticated) {
        return '/auth?redirect=${Uri.encodeComponent(path)}';
      }
      if (path == '/auth' && auth.isAuthenticated) {
        return state.uri.queryParameters['redirect'] ?? '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          redirectTo: state.uri.queryParameters['redirect'],
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => const _AuthCallbackScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen()),
          GoRoute(
            path: '/listings',
            builder: (_, __) => const ListingsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => DestinationDetailScreen(
                  id: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/stories', builder: (_, __) => const StoriesScreen()),
          GoRoute(
            path: '/gems/:id',
            builder: (context, state) => GemDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/stories/:id',
            builder: (context, state) => StoryDetailScreen(id: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/drop-gem', builder: (_, __) => const AddGemScreen()),
      GoRoute(path: '/submit-story', builder: (_, __) => const SubmitStoryScreen()),
      GoRoute(path: '/hikes', builder: (_, __) => const HikesScreen()),
      GoRoute(path: '/log-hike', builder: (_, __) => const LogHikeScreen()),
      GoRoute(path: '/splits', builder: (_, __) => const SplitsScreen()),
      GoRoute(
        path: '/splits/:id',
        builder: (context, state) =>
            SplitDetailScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    ],
  );
}

class _AuthCallbackScreen extends StatefulWidget {
  const _AuthCallbackScreen();
  @override
  State<_AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<_AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}

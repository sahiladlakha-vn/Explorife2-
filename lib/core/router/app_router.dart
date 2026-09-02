import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/auth_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/home/destination_landing_screen.dart';
import '../../screens/explore/explore_screen.dart';
import '../../screens/listings/listings_screen.dart';
import '../../screens/listings/destination_detail_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/gems/gem_detail_screen.dart';
import '../../screens/gems/placement_screen.dart';
import '../../screens/attractions/attraction_detail_screen.dart';
import '../../screens/attractions/attraction_form_screen.dart';
import '../../screens/attractions/attraction_moderation_screen.dart';
import '../../models/attraction.dart';
import '../../screens/tours/tours_list_screen.dart';
import '../../screens/tours/tour_detail_screen.dart';
import '../../screens/stories/stories_screen.dart';
import '../../screens/stories/story_detail_screen.dart';
import '../../screens/stories/submit_story_screen.dart';
import '../../screens/hikes/hikes_screen.dart';
import '../../screens/hikes/log_hike_screen.dart';
import '../../screens/splits/splits_screen.dart';
import '../../screens/splits/split_detail_screen.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../widgets/common/app_shell.dart';
import '../../routes/trip_routes.dart';

// TODO(routing): routes currently overlay the shell by tree placement (siblings
// of ShellRoute) rather than an explicit rootNavigatorKey. Revisit if deep
// linking or navigator-key-based tests are needed — see also trip_routes.dart.

// Matched by startsWith, so '/trips' covers '/trips/new' and '/trips/:id/builder'.
const _protectedRoutes = {
  '/profile',
  '/drop-gem',
  '/submit-story',
  '/log-hike',
  '/splits',
  '/trips',
  '/attractions/new',
  '/attractions/moderation',
};

class AppRouter {
  /// Build the router with [authRefresh] wired to `refreshListenable` so that
  /// `redirect` re-runs when auth resolves (loading → resolved). Without this,
  /// a cold-boot deep link is evaluated once while `auth.loading` is still true
  /// (every guard returns null), and the router never re-evaluates — leaving the
  /// user stranded on the initial route (e.g. stuck on /onboarding) and firing
  /// stale imperative navigation as auth churns.
  static GoRouter create(Listenable authRefresh) => GoRouter(
        refreshListenable: authRefresh,
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
              GoRoute(
                // Destination Detail — opened from a destination-scoped card
                // in Home's "Explore Ideas" rail, or from ListingsScreen's
                // search-results Destinations tab. Both entry points resolve
                // real coordinates first and land here the same way (see
                // destination_landing_screen.dart).
                path: '/destinations/explore',
                builder: (_, state) {
                  final q = state.uri.queryParameters;
                  return DestinationLandingScreen(
                    cityName: q['name'] ?? 'this destination',
                    lat: double.tryParse(q['lat'] ?? ''),
                    lng: double.tryParse(q['lng'] ?? ''),
                  );
                },
              ),
              GoRoute(
                  path: '/explore', builder: (_, __) => const ExploreScreen()),
              GoRoute(
                path: '/listings',
                // Merged search/discovery screen — Home's search bar passes
                // extra: true to land it focused on the search field instead of
                // the default Browse view; every other entry point (SEE ALL,
                // the bottom nav's compass tab) omits extra, same as before.
                // Home's category chips pass ?category=<Gem.categories value>
                // instead (a separate query param, not `extra` — the two never
                // apply together) to land pre-filtered.
                builder: (_, state) => ListingsScreen(
                  autofocusSearch: state.extra == true,
                  initialCategory: state.uri.queryParameters['category'],
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => DestinationDetailScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: '/profile',
                builder: (_, state) =>
                    ProfileScreen(deepLink: state.extra as ProfileDeepLink?),
              ),
              GoRoute(
                  path: '/stories', builder: (_, __) => const StoriesScreen()),
              GoRoute(
                // Opened from a Mapbox-sourced POI card (e.g. a destination
                // landing page's "Top things to do"/"Top attractions" list)
                // — no saved_gems row exists for these, so the POI itself is
                // passed via `extra` rather than looked up by id. MUST come
                // before '/gems/:id' below — GoRouter matches in declaration
                // order, and ':id' would otherwise greedily match "poi".
                path: '/gems/poi',
                builder: (context, state) =>
                    GemDetailScreen.fromPoi(poi: state.extra as NearbyPoi),
              ),
              GoRoute(
                path: '/gems/:id',
                builder: (context, state) =>
                    GemDetailScreen(id: state.pathParameters['id']!),
              ),
              // Trail/Tour — bookable, priced experiences, deliberately a
              // separate namespace from both '/gems' (free, crowdsourced
              // spots) and '/trips' (a user's own itinerary planning) to
              // avoid any confusion between the three.
              GoRoute(
                path: '/tours',
                builder: (_, __) => const ToursListScreen(),
              ),
              GoRoute(
                path: '/tours/:id',
                builder: (context, state) =>
                    TourDetailScreen(id: state.pathParameters['id']!),
              ),
              // Attraction — the first of 8 business profile types. Order
              // matters: '/attractions/new' and '/attractions/moderation'
              // MUST come before '/attractions/:id', or GoRouter's
              // declaration-order matching would greedily swallow both as
              // an ":id" of "new"/"moderation" (same gotcha as '/gems/poi'
              // above).
              GoRoute(
                path: '/attractions/new',
                builder: (_, __) => const AttractionFormScreen(),
              ),
              GoRoute(
                path: '/attractions/moderation',
                builder: (_, __) => const AttractionModerationScreen(),
              ),
              GoRoute(
                path: '/attractions/:id/edit',
                builder: (context, state) => AttractionFormScreen(
                  existing: state.extra as Attraction?,
                ),
              ),
              GoRoute(
                path: '/attractions/:id',
                builder: (context, state) =>
                    AttractionDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: '/stories/:id',
                builder: (context, state) =>
                    StoryDetailScreen(id: state.pathParameters['id']!),
              ),
              // Nested here (unlike its sibling trip routes below) so it gets the
              // shell's persistent bottom nav, matching every other screen.
              tripBuilderRoute(),
            ],
          ),
          GoRoute(
            path: '/drop-gem',
            builder: (_, state) {
              final extra = state.extra as Map?;
              return PlacementScreen(
                initialLat: (extra?['lat'] as num?)?.toDouble(),
                initialLng: (extra?['lng'] as num?)?.toDouble(),
              );
            },
          ),
          GoRoute(
              path: '/submit-story',
              builder: (_, __) => const SubmitStoryScreen()),
          // Trip Builder feature routes (overlay the shell, like the siblings above).
          ...tripRoutes(),
          GoRoute(path: '/hikes', builder: (_, __) => const HikesScreen()),
          GoRoute(path: '/log-hike', builder: (_, __) => const LogHikeScreen()),
          GoRoute(path: '/splits', builder: (_, __) => const SplitsScreen()),
          GoRoute(
            path: '/splits/:id',
            builder: (context, state) =>
                SplitDetailScreen(groupId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/onboarding',
              builder: (_, __) => const OnboardingScreen()),
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
      backgroundColor: AppTheme.lightSurface,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}

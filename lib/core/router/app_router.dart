import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/pending_action.dart';
import '../../core/services/resolve_pending_action.dart';
import '../../core/theme/app_theme.dart';
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
import '../../screens/restaurants/restaurant_detail_screen.dart';
import '../../screens/restaurants/restaurant_form_screen.dart';
import '../../screens/restaurants/restaurant_moderation_screen.dart';
import '../../models/restaurant.dart';
import '../../screens/tours/tours_list_screen.dart';
import '../../screens/tours/tour_detail_screen.dart';
import '../../screens/stories/stories_screen.dart';
import '../../screens/stories/story_detail_screen.dart';
import '../../screens/stories/submit_story_screen.dart';
import '../../screens/hikes/hikes_screen.dart';
import '../../screens/hikes/log_hike_screen.dart';
import '../../screens/splits/splits_screen.dart';
import '../../screens/splits/split_detail_screen.dart';
import '../../widgets/common/app_shell.dart';
import '../../routes/trip_routes.dart';

// TODO(routing): routes currently overlay the shell by tree placement (siblings
// of ShellRoute) rather than an explicit rootNavigatorKey. Revisit if deep
// linking or navigator-key-based tests are needed — see also trip_routes.dart.

class AppRouter {
  /// No forced sign-in gate anymore — every session starts as a real
  /// (anonymous) guest automatically (see AuthProvider._init), so there's
  /// no "unauthenticated" state left to redirect away from. The app
  /// launches straight into Home; '/auth' is reachable only voluntarily
  /// (e.g. a "Sign in" link in Profile) and specific write actions gate
  /// themselves contextually via requireAccount (sign_in_sheet.dart)
  /// instead of one global route guard.
  ///
  /// [authRefresh] is still wired to `refreshListenable` so GoRouter
  /// rebuilds once auth actually resolves post-launch (matters for e.g.
  /// Profile reading `auth.user` before the cold-boot session lands).
  static GoRouter create(Listenable authRefresh) => GoRouter(
        refreshListenable: authRefresh,
        initialLocation: '/home',
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
              // an ":id" of "new"/"moderation".
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
              // Restaurant — the second of 8 business profile types, same
              // declaration-order gotcha as Attraction above: 'new' and
              // 'moderation' must come before ':id'.
              GoRoute(
                path: '/restaurants/new',
                builder: (_, __) => const RestaurantFormScreen(),
              ),
              GoRoute(
                path: '/restaurants/moderation',
                builder: (_, __) => const RestaurantModerationScreen(),
              ),
              GoRoute(
                path: '/restaurants/:id/edit',
                builder: (context, state) => RestaurantFormScreen(
                  existing: state.extra as Restaurant?,
                ),
              ),
              GoRoute(
                path: '/restaurants/:id',
                builder: (context, state) =>
                    RestaurantDetailScreen(id: state.pathParameters['id']!),
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
    _resume();
  }

  /// If a write action was deferred by requireAccount() before this OAuth
  /// redirect fired (see PendingAction/sign_in_sheet.dart), re-run it now
  /// that sign-in actually completed, then land on wherever that action's
  /// own result lives — never just a blind '/home', or the whole point of
  /// resuming would be lost.
  Future<void> _resume() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final pending = await PendingAction.takeAndClear();
    final destination =
        pending == null ? '/home' : await resolvePendingAction(context, pending);
    if (mounted) context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}

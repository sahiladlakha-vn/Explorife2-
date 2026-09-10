import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/pending_action.dart';
import '../../core/services/resolve_pending_action.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/oauth_button.dart';
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
        // Defense-in-depth against two DIFFERENT failure shapes, not one:
        // (1) a genuinely unmatched location (typo'd link, stale bookmark);
        // (2) GoTrue's error redirect for certain link-callback failures
        // (e.g. identity_already_exists) — which, it turns out, bypasses
        // AuthProvider's custom redirectTo entirely and lands on the
        // project's bare Site URL instead, error encoded as ordinary query
        // params. That never matches any GoRoute (so _AuthCallbackScreen's
        // own '/auth/callback' handling never even runs) and falls through
        // to here — Uri.base.queryParameters (the actual browser location)
        // is what still lets this be recognized and shown with the same
        // friendly, code-specific message rather than a generic 404.
        errorBuilder: (context, state) {
          final params = Uri.base.queryParameters;
          final authError = _friendlyAuthError(params);
          if (authError != null) {
            // Same reasoning as _AuthCallbackScreen's error branch: the
            // sign-in didn't complete, so any action queued before it
            // shouldn't be silently resumed on the next successful one.
            PendingAction.takeAndClear();
            return _AuthErrorScreen(
                message: authError, errorCode: params['error_code']);
          }
          return Scaffold(
            backgroundColor: AppTheme.lightSurface,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off,
                          size: 48, color: AppTheme.lightMute),
                      const SizedBox(height: 16),
                      const Text('Page not found',
                          style: TextStyle(
                              color: AppTheme.lightInk, fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Back to Explorife'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
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
                // extra: ProfileDeepLink still wins when a caller has one
                // already (Trip Builder's back button, e.g.) — the simpler
                // '?tab=N' query param is for callers that don't depend on
                // profile_screen.dart at all (ProfilePanel, app_shell.dart's
                // ecosystem), which importing ProfileDeepLink directly would
                // create a real import cycle for (app_shell -> profile_panel
                // -> profile_screen -> app_shell, for AppShellScope).
                builder: (_, state) {
                  final extra = state.extra;
                  if (extra is ProfileDeepLink) {
                    return ProfileScreen(deepLink: extra);
                  }
                  final tab =
                      int.tryParse(state.uri.queryParameters['tab'] ?? '');
                  return ProfileScreen(
                      deepLink: tab != null ? ProfileDeepLink(tab: tab) : null);
                },
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

/// Shared by both _AuthCallbackScreen (the normal '/auth/callback' landing)
/// and AppRouter's errorBuilder (GoTrue's bare-Site-URL fallback for certain
/// link-callback failures — see errorBuilder's own doc comment) so the two
/// paths that can both receive the exact same GoTrue error show identical
/// copy rather than one showing a friendly message and the other a generic
/// 404 depending on which of the two ever happened to catch it.
String? _friendlyAuthError(Map<String, String> params) {
  final code = params['error_code'];
  if (code == null) return null;
  switch (code) {
    case 'identity_already_exists':
      return 'That Google account is already linked to a different '
          'Explorife profile. Try a different Google account, or sign '
          'out of this guest session first and sign in with that '
          'account directly.';
    default:
      final description = params['error_description'];
      return description != null
          ? description.replaceAll('+', ' ')
          : 'Sign-in failed. Please try again.';
  }
}

class _AuthErrorScreen extends StatefulWidget {
  const _AuthErrorScreen({required this.message, required this.errorCode});

  final String message;
  final String? errorCode;

  @override
  State<_AuthErrorScreen> createState() => _AuthErrorScreenState();
}

class _AuthErrorScreenState extends State<_AuthErrorScreen> {
  bool _retrying = false;
  String? _retryError;

  /// The recovery action for `identity_already_exists` specifically: the
  /// Google identity already belongs to a real account, so rather than
  /// leave the user stuck on an error, offer to just sign into THAT
  /// account directly (see AuthProvider.signInWithGoogleDirect's own doc).
  Future<void> _signInWithThisAccount() async {
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      await context.read<AuthProvider>().signInWithGoogleDirect();
      // No further UI update expected on web past this point — the page
      // navigates away for the fresh OAuth round-trip.
    } catch (e) {
      if (mounted) {
        setState(() {
          _retrying = false;
          _retryError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offerDirectSignIn = widget.errorCode == 'identity_already_exists';
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            // Without a cap here, a wide desktop viewport gives this long a
            // sentence enough room to lay out as one unwrapped line spanning
            // almost the full screen instead of a readable, centered
            // paragraph — 420 keeps it wrapping at a normal paragraph width
            // on any viewport, not just narrow ones.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppTheme.lightMute),
                  const SizedBox(height: 16),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppTheme.lightInk, fontSize: 15),
                  ),
                  if (_retryError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _retryError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (offerDirectSignIn) ...[
                    OAuthButton(
                      label: 'Sign in with this account',
                      icon: googleIcon,
                      loading: _retrying,
                      onTap: _signInWithThisAccount,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _retrying ? null : () => context.go('/home'),
                      child: const Text('Back to Explorife'),
                    ),
                  ] else
                    ElevatedButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Back to Explorife'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCallbackScreen extends StatefulWidget {
  const _AuthCallbackScreen();
  @override
  State<_AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<_AuthCallbackScreen> {
  // Guards both branches below so a rebuild (e.g. from GoRouterState still
  // resolving) never double-fires _resume()'s navigation or discards a
  // second PendingAction. Deliberately set from build(), not initState —
  // GoRouterState.of(context) reads an InheritedWidget-backed ModalRoute
  // that isn't safely available that early.
  bool _handled = false;

  /// If a write action was deferred by requireAccount() before this OAuth
  /// redirect fired (see PendingAction/sign_in_sheet.dart), re-run it now
  /// that sign-in actually completed, then land on wherever that action's
  /// own result lives — never just a blind '/home', or the whole point of
  /// resuming would be lost.
  Future<void> _resume() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final pending = await PendingAction.takeAndClear();
    final destination = pending == null
        ? '/home'
        : await resolvePendingAction(context, pending);
    if (mounted) context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    // GoTrue redirects here with `?error=...&error_code=...&error_description=...`
    // (not a session) when the OAuth attempt itself failed server-side —
    // e.g. the Google account picked is already linked to a different,
    // older real account (`identity_already_exists`). Some failures in
    // this same class instead land on AppRouter's errorBuilder (bare Site
    // URL fallback) rather than here — see _friendlyAuthError's own doc.
    final params = GoRouterState.of(context).uri.queryParameters;
    final error = _friendlyAuthError(params);

    if (error != null) {
      if (!_handled) {
        _handled = true;
        // The sign-in didn't actually complete — resuming whatever gated
        // action queued this attempt would be wrong (and possibly repeat
        // it against the wrong account once the user retries). One-shot
        // clear, same as the success path already does.
        PendingAction.takeAndClear();
      }
      return _AuthErrorScreen(message: error, errorCode: params['error_code']);
    }

    if (!_handled) {
      _handled = true;
      _resume();
    }
    return const Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}

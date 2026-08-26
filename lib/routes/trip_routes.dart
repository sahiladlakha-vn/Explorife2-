import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/trip_setup/trip_setup_sheet.dart';
import '../screens/trip_builder/trip_builder_screen.dart';
import '../screens/trip_summary/trip_summary_screen.dart';
import '../screens/trips/trips_list_screen.dart';

/// Trip routes other than the builder. Spread into the top-level `routes:`
/// list as siblings of `ShellRoute` so they overlay the bottom nav — matching
/// the house pattern used by `/drop-gem`, `/splits/:id`, etc. (no root
/// navigator key in this app). The builder route is deliberately NOT here —
/// see [tripBuilderRoute].
/// Protected: '/trips' is in _protectedRoutes (app_router.dart), matched by
/// startsWith, so unauthenticated hits redirect before createTrip can run.
List<RouteBase> tripRoutes() => [
      // Bare index — the full trip list, reached from the drawer's "My Trips"
      // tile. Registered before `/trips/new` in source but GoRouter matches
      // literal segments before parameterized ones regardless of order, so
      // this doesn't shadow `/trips/new`.
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripsListScreen(),
      ),
      GoRoute(
        // ?location=&lat=&lng= seeds Step 1's destination field — e.g. Home's
        // "Where to next?" destination browser jumping straight into trip
        // creation for a tapped city (see destination_browser_sheet.dart).
        // Every other call site omits these and gets the same blank draft
        // as before.
        path: '/trips/new',
        pageBuilder: (context, state) {
          final q = state.uri.queryParameters;
          return _ModalSheetPage(
            key: state.pageKey,
            child: TripSetupSheet(
              initialLocation: q['location'],
              initialLat: double.tryParse(q['lat'] ?? ''),
              initialLng: double.tryParse(q['lng'] ?? ''),
            ),
          );
        },
      ),
      // Explicit `/summary` alias, registered before the bare `:id` canonical so
      // the more-specific path is matched first.
      GoRoute(
        path: '/trips/:id/summary',
        builder: (context, state) => TripSummaryScreen(
          tripId: state.pathParameters['id']!,
        ),
      ),
      // NOTE: the trip route map (tapped from the Overview card) is a
      // showDialog modal (see trip_map_dialog.dart), not a routed screen —
      // nothing links to it by URL, so it doesn't need a GoRoute entry.
      // Canonical landing. Listed AFTER `/trips/new` so the literal `new` route
      // still wins that segment; `:id` only captures real trip ids.
      GoRoute(
        path: '/trips/:id',
        builder: (context, state) => TripSummaryScreen(
          tripId: state.pathParameters['id']!,
        ),
      ),
    ];

/// Trip Builder's route, registered inside `ShellRoute` (unlike its siblings
/// above) so it gets the same `AppShell`/`BottomNav` instance as every other
/// screen — the persistent nav bar that Profile/Overview etc. show. Kept
/// separate from [tripRoutes] specifically for that placement; nothing else
/// about it differs from a normal trip route.
GoRoute tripBuilderRoute() => GoRoute(
      path: '/trips/:id/builder',
      builder: (context, state) => TripBuilderScreen(
        tripId: state.pathParameters['id']!,
        // e.g. My Trip's "+ Add activity" links here with ?day=N so the
        // builder lands on the day the user was already looking at.
        initialDay: int.tryParse(state.uri.queryParameters['day'] ?? ''),
      ),
    );

/// A [Page] that presents its child as a modal bottom sheet. Backdrop is
/// transparent because the sheet body draws its own dark surface with rounded
/// top corners — the default white would flash during the open animation.
/// `isScrollControlled` lets Step 1's vibe grid exceed half height.
class _ModalSheetPage<T> extends Page<T> {
  const _ModalSheetPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
        settings: this,
        builder: (_) => child,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        useSafeArea: true,
      );
}

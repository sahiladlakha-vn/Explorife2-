import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/trip_setup/trip_setup_sheet.dart';
import '../screens/trip_builder/trip_builder_screen.dart';

/// Trip Builder routes. Spread into the top-level `routes:` list as siblings of
/// `ShellRoute` so they overlay the bottom nav — matching the house pattern
/// used by `/drop-gem`, `/splits/:id`, etc. (no root navigator key in this app).
/// Protected: '/trips' is in _protectedRoutes (app_router.dart), matched by
/// startsWith, so unauthenticated hits redirect before createTrip can run.
List<RouteBase> tripRoutes() => [
      GoRoute(
        // TODO(prefill): accept a ?location= query param to seed the draft.
        path: '/trips/new',
        pageBuilder: (context, state) => _ModalSheetPage(
          key: state.pageKey,
          child: const TripSetupSheet(),
        ),
      ),
      GoRoute(
        path: '/trips/:id/builder',
        builder: (context, state) => TripBuilderScreen(
          tripId: state.pathParameters['id']!,
        ),
      ),
    ];

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

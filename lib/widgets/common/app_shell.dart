import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import 'bottom_nav.dart';
import 'side_drawer.dart';
import 'side_nav.dart';

/// Exposes the app-shell drawer to descendant screens so the Home avatar,
/// the map menu button, etc. can open the same panel without owning a Scaffold.
class AppShellScope extends InheritedWidget {
  final VoidCallback openDrawer;
  const AppShellScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  static AppShellScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>()!;

  @override
  bool updateShouldNotify(AppShellScope oldWidget) => false;
}

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // (route, icon, label) — index order is the contract with BottomNav/SideNav
  // and the route↔index mapping below. BottomNav (mobile) stays icon-only by
  // design; SideNav (desktop) shows the label too — same 5 destinations and
  // routes either way, this is presentation, not a nav restructure.
  static const _tabs = [
    ('/home',     Icons.home_outlined,          'Home'),
    ('/explore',  Icons.map_outlined,           'Explore'),
    ('/stories',  Icons.menu_book_outlined,     'Stories'),
    ('/listings', Icons.explore_outlined,       'Listings'),
    ('/profile',  Icons.person_outline_rounded, 'Profile'),
  ];

  int _indexFromLocation(String location) {
    if (location.startsWith('/explore'))  return 1;
    if (location.startsWith('/stories'))  return 2;
    if (location.startsWith('/listings')) return 3;
    if (location.startsWith('/profile'))  return 4;
    // Trip Builder isn't one of the 5 primary tabs (reached from Profile) —
    // no pill should light up while it's open.
    if (location.startsWith('/trips'))    return -1;
    return 0;
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  // Every tab is a real peer route now (Profile included). The hamburger menu —
  // not the nav bar — owns the drawer.
  void _onTap(int i) => context.go(_tabs[i].$1);

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);

    // Same Scaffold shape either width — key, drawer, background, and the
    // AppShellScope-wrapped child are identical. Only the nav placement
    // differs: a bottom bar (mobile) vs. a left rail feeding the body via a
    // Row (desktop), per Breakpoints.isDesktop. This is one shell branching
    // internally, not two shell implementations — see Breakpoints' doc for
    // why 900 is the shared threshold.
    final isDesktop = Breakpoints.isDesktop(context);

    return Scaffold(
      key: _scaffoldKey,
      // Explicit light background — MaterialApp.router still resolves
      // AppTheme.darkTheme (the per-screen re-theme work never touched the
      // root ThemeData, only individual Scaffolds), so leaving this unset
      // fell back to the dark theme's near-black scaffoldBackgroundColor
      // everywhere this outer Scaffold peeks through — most visibly in the
      // reserved strip behind BottomNav's translucent glass pill, which
      // reads as washed-out over that dark backdrop instead of the light
      // one it was designed for.
      backgroundColor: AppTheme.lightSurface,
      drawer: const SideDrawer(),
      drawerEnableOpenDragGesture: false,
      body: AppShellScope(
        openDrawer: _openDrawer,
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SideNav(
                    destinations: [for (final t in _tabs) (t.$2, t.$3)],
                    currentIndex: currentIndex,
                    onTap: _onTap,
                    onOpenMenu: _openDrawer,
                  ),
                  Expanded(child: widget.child),
                ],
              )
            : widget.child,
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNav(
              icons: [for (final tab in _tabs) tab.$2],
              currentIndex: currentIndex,
              onTap: _onTap,
            ),
    );
  }
}

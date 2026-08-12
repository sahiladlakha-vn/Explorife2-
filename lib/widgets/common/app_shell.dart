import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'bottom_nav.dart';
import 'side_drawer.dart';

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

  // (route, icon) — index order is the contract with BottomNav and the
  // route↔index mapping below. Label-less, so a single icon per item.
  static const _tabs = [
    ('/home',     Icons.home_outlined),
    ('/explore',  Icons.map_outlined),
    ('/stories',  Icons.menu_book_outlined),
    ('/listings', Icons.explore_outlined),
    ('/profile',  Icons.person_outline_rounded),
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

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SideDrawer(),
      drawerEnableOpenDragGesture: false,
      body: AppShellScope(openDrawer: _openDrawer, child: widget.child),
      bottomNavigationBar: BottomNav(
        icons: [for (final tab in _tabs) tab.$2],
        currentIndex: currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    ('/home',     Icons.home_outlined,         Icons.home,           'Home'),
    ('/explore',  Icons.map_outlined,           Icons.map,            'Map'),
    ('/stories',  Icons.menu_book_outlined,     Icons.menu_book,      'Stories'),
    ('/listings', Icons.explore_outlined,       Icons.explore,        'Discover'),
    ('/profile',  Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  int _indexFromLocation(String location) {
    if (location.startsWith('/explore'))  return 1;
    if (location.startsWith('/stories'))  return 2;
    if (location.startsWith('/listings')) return 3;
    if (location.startsWith('/profile'))  return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.bg,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          backgroundColor: AppTheme.bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => context.go(_tabs[i].$1),
          destinations: _tabs.asMap().entries.map((e) {
            final isSelected = e.key == currentIndex;
            final tab = e.value;
            return NavigationDestination(
              icon: Icon(tab.$2, color: AppTheme.textSecondary),
              selectedIcon: Icon(tab.$3, color: AppTheme.primary),
              label: tab.$4,
            );
          }).toList(),
        ),
      ),
    );
  }
}

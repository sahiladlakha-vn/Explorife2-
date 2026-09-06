import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../app_network_image.dart';
import 'bottom_nav.dart';
import 'side_nav.dart';

/// Exposes the mobile app-shell "menu" action to descendant screens so the
/// Profile header's burger can jump straight to the full Profile screen
/// without owning a Scaffold. There used to be a slide-out Drawer
/// (SideDrawer) behind this — it's been removed in favor of that direct
/// navigation, since Profile's own tabs (Trips/Saved Gems/Stories/Splits/
/// Settings) already cover everything the drawer used to summarize.
///
/// Tablet/desktop's hamburger (see `_TopBar` below) is unrelated — it
/// opens/closes the slide-in [SideNav] panel, not this.
class AppShellScope extends InheritedWidget {
  final VoidCallback openMenu;
  const AppShellScope({
    super.key,
    required this.openMenu,
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

class _CloseDrawerIntent extends Intent {
  const _CloseDrawerIntent();
}

class _AppShellState extends State<AppShell> {
  // SideNav is hidden off-screen by default (see build()) and slides in
  // over the page content — below the sticky top bar, never pushing/
  // resizing it — when the top bar's hamburger is tapped.
  bool _sideNavOpen = false;

  // Keyboard focus contract: opening the panel moves focus to its close
  // button (the first, always-present focusable control inside it);
  // closing it — by any of the 3 methods (scrim tap, ✕, destination pick)
  // — returns focus to the hamburger that opened it. Escape closes it too
  // (see the Shortcuts/Actions wrap in build()).
  final FocusNode _hamburgerFocusNode = FocusNode(debugLabel: 'hamburger');
  final FocusNode _drawerCloseFocusNode = FocusNode(debugLabel: 'drawer-close');

  void _openSideNav() {
    setState(() => _sideNavOpen = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _drawerCloseFocusNode.requestFocus());
  }

  void _closeSideNav() {
    if (!_sideNavOpen) return;
    setState(() => _sideNavOpen = false);
    _hamburgerFocusNode.requestFocus();
  }

  void _toggleSideNav() => _sideNavOpen ? _closeSideNav() : _openSideNav();

  // (route, icon, label) — index order is the contract with BottomNav/SideNav
  // and the route↔index mapping below. BottomNav (mobile) stays icon-only by
  // design; SideNav (tablet/desktop) shows the label too — same 5
  // destinations and routes either way, this is presentation, not a nav
  // restructure. Labels are Home/Map/Guide/Explore/Profile — Map/Guide/
  // Explore rename what used to show as Explore/Stories/Listings so the
  // drawer reads the way the desktop-layout spec named these 5 spots;
  // routes and icons are unchanged.
  static const _tabs = [
    ('/home',     Icons.home_outlined,          'Home'),
    ('/explore',  Icons.map_outlined,           'Map'),
    ('/stories',  Icons.menu_book_outlined,     'Guide'),
    ('/listings', Icons.explore_outlined,       'Explore'),
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

  // No more slide-out drawer — the burger/menu action just opens the full
  // Profile screen, same as tapping the Profile tab.
  void _openMenu() => context.go('/profile');

  // Every tab is a real peer route now (Profile included).
  void _onTap(int i) => context.go(_tabs[i].$1);

  @override
  void dispose() {
    _hamburgerFocusNode.dispose();
    _drawerCloseFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);

    // Same Scaffold shape at every tier — background and the
    // AppShellScope-wrapped child are identical. Only the nav placement
    // differs: a bottom bar (phone) vs. a sticky top bar + hamburger-
    // triggered slide-in panel (tablet/desktop), per Breakpoints.tierOf.
    // This is one shell branching internally, not separate shell
    // implementations — see Breakpoints' doc for why phone/tablet/desktop
    // share this one threshold set.
    final tier = Breakpoints.tierOf(context);
    final isPhone = tier == ScreenTier.phone;

    return Scaffold(
      // Lets body content scroll underneath the floating BottomNav pill so
      // its BackdropFilter has something to actually blur — without this,
      // Scaffold lays body/bottomNavigationBar out as stacked siblings and
      // the body stops short, leaving nothing behind the glass to frost.
      // Tablet/desktop have no bottomNavigationBar at all, so they're
      // unaffected by this flag.
      extendBody: true,
      // Explicit light background — MaterialApp.router still resolves
      // AppTheme.darkTheme (the per-screen re-theme work never touched the
      // root ThemeData, only individual Scaffolds), so leaving this unset
      // fell back to the dark theme's near-black scaffoldBackgroundColor
      // everywhere this outer Scaffold peeks through — most visibly in the
      // reserved strip behind BottomNav's translucent glass pill, which
      // reads as washed-out over that dark backdrop instead of the light
      // one it was designed for.
      backgroundColor: AppTheme.lightSurface,
      body: AppShellScope(
        openMenu: _openMenu,
        child: isPhone
            ? widget.child
            : Column(
                children: [
                  _TopBar(
                    tier: tier,
                    hamburgerFocusNode: _hamburgerFocusNode,
                    onMenuTap: _toggleSideNav,
                  ),
                  Expanded(
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.escape):
                            _CloseDrawerIntent(),
                      },
                      child: Actions(
                        actions: {
                          _CloseDrawerIntent: CallbackAction<_CloseDrawerIntent>(
                            onInvoke: (_) {
                              _closeSideNav();
                              return null;
                            },
                          ),
                        },
                        child: Stack(
                          children: [
                            // Content spans the full width — SideNav never
                            // reserves a permanent column, it overlays.
                            Positioned.fill(child: widget.child),

                            // Dimming scrim: only present (and tappable-to-
                            // close) while the panel is open; fades with it.
                            IgnorePointer(
                              ignoring: !_sideNavOpen,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeSideNav,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 320),
                                  curve: Curves.easeOut,
                                  opacity: _sideNavOpen ? 1 : 0,
                                  child: Container(
                                      color:
                                          Colors.black.withValues(alpha: 0.25)),
                                ),
                              ),
                            ),

                            // The panel itself — off-screen left when
                            // closed, slides to x=0 over the content (not
                            // pushing it) when open.
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOut,
                              top: 0,
                              bottom: 0,
                              left: _sideNavOpen ? 0 : -SideNav.width,
                              width: SideNav.width,
                              child: SideNav(
                                destinations: [
                                  for (final t in _tabs) (t.$2, t.$3)
                                ],
                                currentIndex: currentIndex,
                                onTap: (i) {
                                  _closeSideNav();
                                  _onTap(i);
                                },
                                onClose: _closeSideNav,
                                closeFocusNode: _drawerCloseFocusNode,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: isPhone
          ? BottomNav(
              icons: [for (final tab in _tabs) tab.$2],
              currentIndex: currentIndex,
              onTap: _onTap,
            )
          : null,
    );
  }
}

/// Sticky top bar for tablet/desktop: hamburger (opens the drawer), logo,
/// a search field, and the signed-in user's avatar. Phone keeps its own
/// per-screen header (e.g. Home's hero row) instead — this bar only
/// exists at tier != phone, so there's exactly one nav-chrome header per
/// tier, never both at once (see the ☰ Menu duplication note in
/// _AppShellState's tab-rename comment above for why that matters here).
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.tier,
    required this.hamburgerFocusNode,
    required this.onMenuTap,
  });

  final ScreenTier tier;
  final FocusNode hamburgerFocusNode;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = context.watch<AuthProvider>().user?.avatarUrl;
    return Material(
      color: AppTheme.lightSurface,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Menu',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    focusNode: hamburgerFocusNode,
                    onTap: onMenuTap,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.menu, size: 22, color: AppTheme.lightInk),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'Explor',
                    style: GoogleFonts.audiowide(
                        fontSize: 18, color: AppTheme.lightInk, letterSpacing: 0.5),
                  ),
                  TextSpan(
                    text: 'ife',
                    style: GoogleFonts.audiowide(
                        fontSize: 18, color: AppTheme.primary, letterSpacing: 0.5),
                  ),
                ]),
              ),
              const SizedBox(width: 20),
              // Desktop gets a real full-width search field (tap-to-open,
              // matching every other search entry point in this app — none
              // of them run live query state inline, they all hand off to
              // ListingsScreen's Suggestions state). Tablet collapses this
              // to a plain icon button instead: there isn't enough width
              // next to the logo + avatar for a legible full field once the
              // drawer's own 280px overlay width is accounted for, and this
              // still reaches the exact same search experience in one tap.
              Expanded(
                child: tier == ScreenTier.desktop
                    ? _TopBarSearchField(
                        onTap: () => context.go('/listings', extra: true),
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Semantics(
                          button: true,
                          label: 'Search',
                          child: IconButton(
                            onPressed: () =>
                                context.go('/listings', extra: true),
                            icon: const Icon(Icons.search,
                                color: AppTheme.lightMute),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: 'Your profile',
                child: GestureDetector(
                  onTap: () => context.go('/profile'),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.lightBorder),
                      color: AppTheme.lightCard,
                    ),
                    child: ClipOval(
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? AppNetworkImage(url: avatarUrl, fit: BoxFit.cover)
                          : const Icon(Icons.person,
                              size: 18, color: AppTheme.lightMute),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarSearchField extends StatelessWidget {
  const _TopBarSearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search places, activities, and gems',
      child: Material(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 18, color: AppTheme.lightMute),
                SizedBox(width: 8),
                Text('Search places, activities, gems…',
                    style: TextStyle(color: AppTheme.lightMute, fontSize: 13.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

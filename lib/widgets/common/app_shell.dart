import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../app_network_image.dart';
import '../profile/profile_panel.dart';
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
  // resizing it — when the top bar's hamburger is tapped. ProfilePanel is
  // the same idea, mirrored to the right edge, triggered by the top bar's
  // avatar instead. Mutually exclusive — opening one closes the other, so
  // there's never two overlays fighting for the same scrim/Escape key.
  bool _sideNavOpen = false;
  bool _profilePanelOpen = false;

  // Keyboard focus contract (both panels): opening moves focus to the
  // panel's close button (the first, always-present focusable control
  // inside it); closing it — by any of the 3 methods (scrim tap, ✕,
  // selecting something that navigates away) — returns focus to whichever
  // top-bar icon opened it. Escape closes whichever is open (see the
  // Shortcuts/Actions wrap in build()).
  final FocusNode _hamburgerFocusNode = FocusNode(debugLabel: 'hamburger');
  final FocusNode _drawerCloseFocusNode = FocusNode(debugLabel: 'drawer-close');
  final FocusNode _profileIconFocusNode = FocusNode(debugLabel: 'profile-icon');
  final FocusNode _profileCloseFocusNode = FocusNode(debugLabel: 'profile-close');

  void _openSideNav() {
    setState(() {
      _sideNavOpen = true;
      _profilePanelOpen = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _drawerCloseFocusNode.requestFocus());
  }

  void _closeSideNav() {
    if (!_sideNavOpen) return;
    setState(() => _sideNavOpen = false);
    _hamburgerFocusNode.requestFocus();
  }

  void _toggleSideNav() => _sideNavOpen ? _closeSideNav() : _openSideNav();

  void _openProfilePanel() {
    setState(() {
      _profilePanelOpen = true;
      _sideNavOpen = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _profileCloseFocusNode.requestFocus());
  }

  void _closeProfilePanel() {
    if (!_profilePanelOpen) return;
    setState(() => _profilePanelOpen = false);
    _profileIconFocusNode.requestFocus();
  }

  void _toggleProfilePanel() =>
      _profilePanelOpen ? _closeProfilePanel() : _openProfilePanel();

  /// Closes whichever overlay is currently open — the shared scrim and
  /// Escape key both funnel here rather than each needing to know which
  /// panel (if either) is showing.
  void _closeAnyOverlay() {
    _closeSideNav();
    _closeProfilePanel();
  }

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
    _profileIconFocusNode.dispose();
    _profileCloseFocusNode.dispose();
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
                    profileIconFocusNode: _profileIconFocusNode,
                    onProfileTap: _toggleProfilePanel,
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
                              _closeAnyOverlay();
                              return null;
                            },
                          ),
                        },
                        child: Stack(
                          children: [
                            // Content spans the full width — neither panel
                            // reserves a permanent column, both overlay.
                            Positioned.fill(child: widget.child),

                            // Shared dimming scrim: present (and tappable-
                            // to-close) while either panel is open; fades
                            // with it. Only one panel is ever open at once
                            // (see _openSideNav/_openProfilePanel), so
                            // there's no ambiguity about what a tap closes.
                            IgnorePointer(
                              ignoring: !_sideNavOpen && !_profilePanelOpen,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeAnyOverlay,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 320),
                                  curve: Curves.easeOut,
                                  opacity:
                                      (_sideNavOpen || _profilePanelOpen) ? 1 : 0,
                                  child: Container(
                                      color:
                                          Colors.black.withValues(alpha: 0.25)),
                                ),
                              ),
                            ),

                            // SideNav — off-screen left when closed, slides
                            // to x=0 over the content (not pushing it) when
                            // open.
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

                            // ProfilePanel — the same idea mirrored to the
                            // right edge, triggered by the top bar's avatar.
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOut,
                              top: 0,
                              bottom: 0,
                              right: _profilePanelOpen
                                  ? 0
                                  : -ProfilePanel.width,
                              width: ProfilePanel.width,
                              child: ProfilePanel(
                                onClose: _closeProfilePanel,
                                closeFocusNode: _profileCloseFocusNode,
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
    required this.profileIconFocusNode,
    required this.onProfileTap,
  });

  final ScreenTier tier;
  final FocusNode hamburgerFocusNode;
  final VoidCallback onMenuTap;
  final FocusNode profileIconFocusNode;
  final VoidCallback onProfileTap;

  // Saving gems isn't persisted yet — same "coming soon" honesty policy
  // Home's save button uses (see home_screen.dart's _comingSoonSave) — and
  // there's no messaging feature anywhere in this app at all, so this link
  // is deliberately a snackbar, never a route to a screen that doesn't
  // exist.
  void _comingSoonMessages(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages is coming soon')),
    );
  }

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
              const SizedBox(width: 4),
              // Compass icon + single-tone "ExploriFe" wordmark — matches
              // the prototype's `.nav-left` exactly (previously a two-tone
              // "Explor"/"ife" split with no icon).
              const Icon(Icons.explore_outlined,
                  size: 24, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                'ExploriFe',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.lightInk,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 20),
              // Desktop gets a real full-width search field (tap-to-open,
              // matching every other search entry point in this app — none
              // of them run live query state inline, they all hand off to
              // ListingsScreen's Suggestions state). Tablet collapses this
              // to a plain icon button instead: there isn't enough width
              // next to the logo + nav-links + avatar for a legible full
              // field once the drawer's own 280px overlay width is
              // accounted for, and this still reaches the exact same search
              // experience in one tap.
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
              // `.nav-right`'s Account/Favorites/Messages text+icon links —
              // desktop only, same reasoning as the search field collapse
              // above (no room at tablet width). Account and Favorites are
              // real destinations already reachable elsewhere (Profile tab,
              // Saved Gems tab); Messages has no feature behind it anywhere
              // in this app, so it stays a "coming soon" snackbar rather
              // than a fake route.
              if (tier == ScreenTier.desktop) ...[
                const SizedBox(width: 20),
                _NavLink(
                  icon: Icons.person_outline,
                  label: 'Account',
                  onTap: () => context.go('/profile'),
                ),
                const SizedBox(width: 20),
                _NavLink(
                  icon: Icons.favorite_border,
                  label: 'Favorites',
                  // Saved Gems is Profile's tab index 2 — see ProfileDeepLink
                  // in profile_screen.dart. Uses the query-param form (not
                  // extra: ProfileDeepLink(...)) so this file doesn't have to
                  // import profile_screen.dart, which itself imports this
                  // file — see AppShellScope's doc comment above for why
                  // that cycle is avoided elsewhere too.
                  onTap: () => context.go('/profile?tab=2'),
                ),
                const SizedBox(width: 20),
                _NavLink(
                  icon: Icons.chat_bubble_outline,
                  label: 'Messages',
                  onTap: () => _comingSoonMessages(context),
                ),
              ],
              const SizedBox(width: 16),
              Semantics(
                button: true,
                label: 'Your profile',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    focusNode: profileIconFocusNode,
                    onTap: onProfileTap,
                    customBorder: const CircleBorder(),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One `.nav-link` — muted icon+label that darkens on hover, matching the
/// prototype exactly. Desktop-only (see _TopBar.build).
class _NavLink extends StatelessWidget {
  const _NavLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTheme.lightMute),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.lightMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pill-shaped, matching the prototype's `.nav-search` (border-radius: 9999px,
// bg: var(--bg)) — previously a 10px-rounded rect on AppTheme.lightCard.
class _TopBarSearchField extends StatelessWidget {
  const _TopBarSearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search places, activities, and gems',
      child: Material(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
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

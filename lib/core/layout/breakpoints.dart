import 'package:flutter/widgets.dart';

/// Single source of truth for the app's one responsive threshold. Previously
/// inline in `TripBuilderScreen` (`width < 900`, invented independently there
/// for its desktop 3-pane layout) — extracted here so every screen compares
/// against the same number instead of each redefining its own check as the
/// web layout work spreads to more screens.
class Breakpoints {
  const Breakpoints._();

  /// Below this, screens get the mobile (phone-width) layout; at or above,
  /// the desktop layout. Matches the threshold TripBuilderScreen already
  /// shipped with — kept identical rather than picked fresh, so the one
  /// screen already using it doesn't visually shift when everything else
  /// adopts the same constant.
  static const double desktop = 900;

  /// Convenience for the common case (compare the current [BuildContext]'s
  /// full window width). Screens laying out inside something narrower than
  /// the window (e.g. a `LayoutBuilder` inside a side-nav'd body) should
  /// compare their own `constraints.maxWidth` against [desktop] directly
  /// instead — see TripBuilderScreen's body for that shape.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktop;

  static bool isMobile(BuildContext context) => !isDesktop(context);

  /// Width the phone-width nav (BottomNav) gives way to the hamburger + side
  /// drawer pattern at — tablet AND desktop both use the drawer, only the
  /// content grid column counts differ between them (see [ScreenTier]).
  /// Deliberately separate from [desktop]/[isDesktop] above: those stay
  /// exactly as they were (900) for the screens already keyed off them
  /// (TripBuilderScreen's 3-pane layout, Home's desktop-only refresh button,
  /// etc.) — introducing the phone/tablet/desktop split here must not shift
  /// any of that existing, unrelated layout math.
  static const double tablet = 768;

  /// Width the tablet content grid gives way to the wider desktop one at
  /// (more columns). Only meaningful together with [tablet] via [tierOf] —
  /// nothing below this width alone changes without also being past
  /// [tablet] first.
  static const double desktopWide = 1024;

  static ScreenTier tierOf(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopWide) return ScreenTier.desktop;
    if (w >= tablet) return ScreenTier.tablet;
    return ScreenTier.phone;
  }
}

/// The phone/tablet/desktop nav+layout tier — see [Breakpoints.tierOf].
/// Phone keeps BottomNav and single-column rails; tablet and desktop both
/// get the hamburger + slide-in drawer nav, differing only in how many grid
/// columns their content sections use.
enum ScreenTier { phone, tablet, desktop }

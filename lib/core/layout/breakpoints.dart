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
}

/// Single source of truth for the app's recurring "gap between stacked
/// sections" values — mirrors [Breakpoints]'s own rationale (one shared
/// constant instead of every screen re-picking its own number).
///
/// Landed because an audit of Home (lib/screens/home/home_screen.dart) and
/// Profile's My Trip tab (lib/screens/profile/tabs/trips_tab.dart) found two
/// *independently self-consistent* but *mutually different* literal pairs —
/// Home used 20/12, My Trip used 16/10 — for what is structurally the same
/// pattern: a gap between major stacked cards/sections, and a smaller gap
/// between a section's own header and its content. Neither screen was wrong
/// in isolation, but nothing stopped a third screen from picking a third
/// pair. [sectionGap]/[headerGap] give every screen the same numbers to
/// converge on; Home and My Trip are the first two adopters.
class AppSpacing {
  const AppSpacing._();

  /// Gap between one major stacked card/section and the next (e.g. the
  /// profile header block and the tab bar below it, or one card and the
  /// next in a single-column stack). Was Home's 20 / My Trip's 16 — 20 wins
  /// since Home already had more sections leaning on it.
  static const double sectionGap = 20;

  /// Gap between a section's own header (title/label row) and its content
  /// immediately below. Was Home's 12 / My Trip's 10 — 12 wins for the same
  /// reason as [sectionGap].
  static const double headerGap = 12;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Tablet/desktop's slide-in nav panel — the hamburger-triggered drawer
/// (not a persistent rail). Presentation-only: AppShell owns the open/closed
/// state, the slide transition, the scrim, and the hamburger toggle itself
/// (see `_TopBar`/`_AppShellState` in app_shell.dart) — this widget is just
/// the panel's content: logo + close, the same 5 destinations BottomNav
/// uses (icon+label here; mobile stays icon-only by design), and a "Drop a
/// gem" CTA pinned to the bottom.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
    required this.onClose,
    required this.closeFocusNode,
  });

  /// (icon, label) pairs, index-aligned with [currentIndex]/[onTap] — same
  /// contract as BottomNav's `icons` list, just carrying a label too.
  final List<(IconData, String)> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Closes the panel without picking a destination — the ✕ button and the
  /// scrim (in AppShell) both funnel here.
  final VoidCallback onClose;

  /// AppShell requests focus on this when the panel opens, so keyboard
  /// focus lands somewhere sensible inside the drawer rather than nowhere —
  /// the close button is the first, always-present focusable control.
  final FocusNode closeFocusNode;

  static const double width = 280;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppTheme.lightSurface,
        border: Border(right: BorderSide(color: AppTheme.lightBorder)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(6, 0)),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'Explor',
                          style: GoogleFonts.audiowide(
                              fontSize: 17,
                              color: AppTheme.lightInk,
                              letterSpacing: 0.5),
                        ),
                        TextSpan(
                          text: 'ife',
                          style: GoogleFonts.audiowide(
                              fontSize: 17,
                              color: AppTheme.primary,
                              letterSpacing: 0.5),
                        ),
                      ]),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close menu',
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        focusNode: closeFocusNode,
                        onTap: onClose,
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close,
                              size: 20, color: AppTheme.lightMute),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.lightBorder),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _SideNavItem(
                      icon: destinations[i].$1,
                      label: destinations[i].$2,
                      isSelected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _DropGemButton(
                  onTap: () {
                    onClose();
                    context.go('/drop-gem');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One rail entry. Selected styling reuses BottomNav's actual current
/// language — a solid-orange circular glow behind the icon, white icon on
/// top — rather than the pill-tint treatment BottomNav moved away from; the
/// label picks up the same orange + bold weight so the row reads as one
/// selected unit alongside that icon treatment.
class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const double _iconSlot = 40;

  @override
  Widget build(BuildContext context) {
    final iconColor = isSelected ? Colors.white : AppTheme.lightMute;
    final textColor = isSelected ? AppTheme.primary : AppTheme.lightInk;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: _iconSlot,
                    height: _iconSlot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? AppTheme.primary : Colors.transparent,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.45),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(icon, size: 21, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Text(label,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 14.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropGemButton extends StatelessWidget {
  const _DropGemButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Drop a gem',
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Drop a gem',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

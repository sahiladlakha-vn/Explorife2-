import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Desktop-width replacement for [BottomNav] — a persistent left rail with the
/// same destinations as icon+label rows. Presentation-only: AppShell passes it
/// the exact same (route, icon) pairs BottomNav gets, just with a label added
/// for legibility at this width (mobile stays icon-only by design).
///
/// The drawer isn't reachable via a bottom-nav-adjacent gesture at this width,
/// so a menu button up top reuses the same [onOpenMenu] callback AppShell
/// already wires BottomNav's screens to via AppShellScope.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
    required this.onOpenMenu,
  });

  /// (icon, label) pairs, index-aligned with [currentIndex]/[onTap] — same
  /// contract as BottomNav's `icons` list, just carrying a label too.
  final List<(IconData, String)> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onOpenMenu;

  static const double width = 232;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppTheme.lightSurface,
        border: Border(right: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: _MenuButton(onTap: onOpenMenu),
            ),
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
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: const Row(
            children: [
              Icon(Icons.menu, size: 19, color: AppTheme.lightMute),
              SizedBox(width: 10),
              Text('Menu',
                  style: TextStyle(
                      color: AppTheme.lightMute,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
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
    );
  }
}

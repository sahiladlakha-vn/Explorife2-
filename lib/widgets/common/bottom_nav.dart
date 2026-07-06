import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Nav metrics — single source of truth for the bar's geometry/motion so no
/// magic numbers leak into the widgets below.
class _NavMetrics {
  static const double barHeight = 64;
  static const double iconSize = 24;

  /// Minimum tap target — keeps every item ≥48px even when its pill is
  /// collapsed (icon-only resting state).
  static const double minTapTarget = 48;

  /// Horizontal padding inside the pill: tight when resting, wide when
  /// selected so the pill visibly "widens".
  static const double pillPadRest = 12;
  static const double pillPadSelected = 22;

  static const double pillRadius = 22;
  static const Duration animDuration = Duration(milliseconds: 250);
  static const Curve animCurve = Curves.easeInOut;
}

/// A reusable, label-less bottom navigation bar. [currentIndex] is the single
/// source of truth: every item derives its own selected state from it, so there
/// are no duplicated per-item flags. Pass [onTap] to react to taps; the host
/// (router) decides what selection means.
class BottomNav extends StatelessWidget {
  /// Icons in display order. Index alignment is the contract between the host's
  /// route↔index mapping and this bar.
  final List<IconData> icons;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({
    super.key,
    required this.icons,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _NavMetrics.barHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < icons.length; i++)
                NavItem(
                  icon: icons[i],
                  isSelected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single nav entry. All selected styling — orange icon, warm pill, and the
/// horizontal expand — is driven purely by [isSelected] and animated with an
/// [AnimatedContainer]. No labels in any state.
class NavItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pillColor = isSelected
        ? AppTheme.primary.withValues(alpha: AppTheme.navPillOpacity)
        : Colors.transparent;
    final iconColor =
        isSelected ? AppTheme.primary : AppTheme.textSecondary;
    final padH = isSelected
        ? _NavMetrics.pillPadSelected
        : _NavMetrics.pillPadRest;

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_NavMetrics.pillRadius),
        // Guarantees a ≥48px hit area regardless of the collapsed pill width.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _NavMetrics.minTapTarget,
            minHeight: _NavMetrics.minTapTarget,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: _NavMetrics.animDuration,
              curve: _NavMetrics.animCurve,
              padding: EdgeInsets.symmetric(
                horizontal: padH,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(_NavMetrics.pillRadius),
              ),
              child: Icon(icon, size: _NavMetrics.iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

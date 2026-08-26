import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Nav metrics — single source of truth for the bar's geometry/motion so no
/// magic numbers leak into the widgets below.
class _NavMetrics {
  static const double barHeight = 62;
  static const double iconSize = 22;
  static const double itemSize = 44;
  static const Duration animDuration = Duration(milliseconds: 250);
  static const Curve animCurve = Curves.easeOutCubic;
}

/// A reusable, label-less bottom navigation bar — a floating frosted-glass
/// pill rather than a full-width docked strip. [currentIndex] is the single
/// source of truth: every item derives its own selected state from it, so
/// there are no duplicated per-item flags. Pass [onTap] to react to taps; the
/// host (router) decides what selection means.
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
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: _NavMetrics.barHeight,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.lightInk.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
        ),
      ),
    );
  }
}

/// A single nav entry. The active item fills solid orange with a soft glow
/// ring and an inverted (white) icon; resting items are a bare muted icon —
/// matches the mockup's "glowing active icon state" rather than the old
/// widening-pill treatment.
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
    final iconColor = isSelected ? Colors.white : AppTheme.lightMute;

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(
          child: AnimatedContainer(
            duration: _NavMetrics.animDuration,
            curve: _NavMetrics.animCurve,
            width: _NavMetrics.itemSize,
            height: _NavMetrics.itemSize,
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
            child: Icon(icon, size: _NavMetrics.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}

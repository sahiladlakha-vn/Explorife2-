import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';

/// The single Gem category filter row — 'All' plus [Gem.categories], fixed
/// order, single-select (tapping the active chip resets to 'all').
///
/// One implementation, mounted wherever a Gem feed needs filtering: the Gems
/// tab in ListingsScreen's search results, and a destination's scoped Gems
/// feed (DestinationLandingScreen). Extracted from ListingsScreen's original
/// private `_CategoryBar` so both mount points share one state model and
/// styling instead of drifting into two forks.
class CategoryChipRow extends StatelessWidget {
  const CategoryChipRow(
      {super.key, required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // 'all' first (primary reset), then the gem categories.
    final cats = <String>['all', ...Gem.categories];

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          final cat = cats[i];
          final isAll = cat == 'all';
          final isSelected = selected == cat;
          final icon =
              isAll ? Icons.public : AppConstants.gemCategoryIcons[cat]!;
          final label =
              isAll ? 'All' : cat[0].toUpperCase() + cat.substring(1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppTheme.lightInk,
              ),
              label: Text(label),
              selected: isSelected,
              // Tapping the active chip again resets to 'all'; tapping any
              // other chip replaces the current selection.
              onSelected: (_) => onSelect(isSelected ? 'all' : cat),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.lightCard,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.lightInk,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? Colors.transparent : AppTheme.lightBorder,
              ),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }
}

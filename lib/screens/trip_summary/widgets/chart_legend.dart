import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// Colour-key legends for the Summary charts. Both variants render the same
// visual atom — [_LegendChip] (a colour swatch + label) — and differ only in
// their [Wrap] density. The shared code therefore lives in the atom, not in a
// forced common interface.
//
// NOTE: both variants take identical `(String, Color)` data; the split into two
// public widgets is a discovery/readability seam (a future chart legend has an
// obvious neighbour to copy), NOT a data-model difference. `ChartLegend` was
// left un-renamed to avoid touching the donut's call site this round.

/// Donut/pie legend: centred, tighter spacing to tuck under the ring.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  /// (label, colour) pairs, already filtered to the entries worth showing.
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, color) in items)
          _LegendChip(label: label, color: color),
      ],
    );
  }
}

/// Bar-chart legend: slightly looser spacing to sit under the grouped bars.
class BarChartLegend extends StatelessWidget {
  const BarChartLegend({super.key, required this.items});

  /// (label, colour) pairs — same shape as [ChartLegend]. Kept positional (not
  /// the named-record sketch) so both legends read uniformly at the call site.
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, color) in items)
          _LegendChip(label: label, color: color),
      ],
    );
  }
}

/// Shared visual atom for every chart legend: an 8px colour swatch followed by
/// its label. The one place swatch/label styling lives.
class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.lightMute,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

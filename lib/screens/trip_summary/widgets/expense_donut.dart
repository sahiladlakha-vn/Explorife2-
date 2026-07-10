import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/trip.dart';
import 'chart_legend.dart';

/// Budget-by-category donut for the Trip Summary. Renders the four budget
/// buckets (stay / food / activity / transit) as a stroked ring sweeping
/// clockwise from 12 o'clock, each slice's share labelled outside the arc on a
/// hairline connector, the total spend in the ring hole, and a colour legend
/// below.
///
/// Composition (per Refinement 2): the painter draws ring + arc labels +
/// connectors only; the legend is a separate [ChartLegend] widget, and the
/// centre total is a [FittedBox] child stacked over the paint — none of that
/// lives in `paint()`.
///
/// Follows the CustomPainter house pattern in
/// trip_builder/widgets/summary_sidebar.dart: `size.isEmpty` guard,
/// `withValues(alpha:)`, `shouldRepaint => true` with a comment.
class ExpenseDonut extends StatelessWidget {
  const ExpenseDonut({
    super.key,
    required this.categoryTotals,
    this.diameter = 180,
  });

  /// The four zero-filled buckets from `TripProvider.categoryTotals` (VND).
  final Map<String, int> categoryTotals;
  final double diameter;

  // Fixed bucket order so slice colours and the legend stay stable regardless
  // of the incoming map's iteration order.
  static const List<String> _order = ['stay', 'food', 'activity', 'transit'];
  static const Map<String, String> _labels = {
    'stay': 'Stay',
    'food': 'Food',
    'activity': 'Do',
    'transit': 'Move',
  };
  static const Map<String, Color> _colors = {
    'stay': AppTheme.primary,
    'food': AppTheme.teal,
    'activity': AppTheme.purple,
    'transit': AppTheme.pink,
  };

  @override
  Widget build(BuildContext context) {
    final slices = [
      for (final k in _order)
        _DonutSlice(_labels[k]!, categoryTotals[k] ?? 0, _colors[k]!),
    ];
    final total = slices.fold<int>(0, (s, e) => s + e.value);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(diameter),
                painter: _ExpenseDonutPainter(slices),
              ),
              // Centre total. FittedBox scales down so ₫999,999,999 still fits
              // the ring hole at small viewport sizes. Padding keeps the text
              // inside the hole rather than overrunning the ring.
              Padding(
                padding: EdgeInsets.all(diameter * 0.30),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₫${Trip.formatVnd(total, short: true)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'spent',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // composed with legend — arc labels are % only per Decision A;
        // see docs/audits/explorife-triage-audit-2026-07-04.md
        ChartLegend(
          items: [
            for (final s in slices)
              if (s.value > 0) (s.label, s.color),
          ],
        ),
      ],
    );
  }
}

class _DonutSlice {
  const _DonutSlice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _ExpenseDonutPainter extends CustomPainter {
  _ExpenseDonutPainter(this.slices);

  final List<_DonutSlice> slices;

  static const double _ringThickness = 16;
  static const double _labelGutter = 46; // room outside the ring for labels
  static const double _connector = 8; // hairline length from arc edge to label
  static const double _minLabelFraction = 0.03; // hide labels under 3%

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Reserve the gutter so outside labels aren't clipped by the paint bounds.
    final ringRadius = min(size.width, size.height) / 2 - _labelGutter;
    if (ringRadius <= 0) return;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringThickness
      ..strokeCap = StrokeCap.butt;

    final total = slices.fold<int>(0, (s, e) => s + e.value);

    // Degenerate: nothing spent yet — faint placeholder ring, no labels.
    if (total == 0) {
      ring.color = AppTheme.divider;
      canvas.drawCircle(center, ringRadius, ring);
      return;
    }

    final rect = Rect.fromCircle(center: center, radius: ringRadius);
    const startAngle = -pi / 2; // 12 o'clock
    var angle = startAngle;

    // Single-category case is handled naturally: frac == 1 → a full-circle arc,
    // one label, no collisions.
    for (final s in slices) {
      if (s.value == 0) continue; // skip empty buckets entirely
      final frac = s.value / total;
      final sweep = frac * 2 * pi; // clockwise (positive sweep, y-down)
      ring.color = s.color;
      canvas.drawArc(rect, angle, sweep, false, ring);
      // TODO(donut-labels): revisit if small trips look cluttered — may want an
      // absolute-value threshold too, not just the percentage one.
      if (frac >= _minLabelFraction) {
        _paintLabel(canvas, center, ringRadius, angle + sweep / 2, frac);
      }
      angle += sweep;
    }
  }

  /// Draws a hairline from the arc's outer edge outward, then the "<n>%" text
  /// just past the elbow — left-aligned on the right half, right-aligned on the
  /// left half so text always grows away from the ring. Category name is not
  /// repeated here; the legend below the donut carries it.
  void _paintLabel(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double midAngle,
    double frac,
  ) {
    // TODO(donut-labels): add collision detection if a user reports overlap
    // between adjacent small slices' labels.
    final dir = Offset(cos(midAngle), sin(midAngle));
    final arcEdge = center + dir * (ringRadius + _ringThickness / 2);
    final elbow = center + dir * (ringRadius + _ringThickness / 2 + _connector);

    canvas.drawLine(
      arcEdge,
      elbow,
      Paint()
        ..color = AppTheme.textSecondary.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    final onRight = cos(midAngle) >= 0;
    final tp = TextPainter(
      text: TextSpan(
        text: '${(frac * 100).round()}%',
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        onRight ? elbow.dx + 4 : elbow.dx - 4 - tp.width,
        elbow.dy - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ExpenseDonutPainter old) => true;
  // Repaint every build — cheap for ≤6 categories and avoids memoization
  // gymnastics. Matches the _BarsPainter / _RoutePainter house pattern.
}

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/trip.dart';
import 'chart_legend.dart';

/// One category's planned-vs-actual pair, in whole VND. [planned]'s data source
/// is a pending wiring decision (see PlannedVsActualChart doc); this widget is
/// decoupled from it — it renders whatever pairs it's given.
class CategorySpend {
  const CategorySpend(this.label, this.planned, this.actual);
  final String label;
  final int planned;
  final int actual;
}

/// Grouped bar chart: two bars per category (planned + actual), categories along
/// the x-axis, a currency reference axis on the left. Below it, a two-item
/// [BarChartLegend] distinguishing planned from actual.
///
/// Follows the CustomPainter house pattern in
/// trip_builder/widgets/summary_sidebar.dart: `size.isEmpty` guard,
/// `withValues(alpha:)`, `shouldRepaint => true` with a comment.
///
/// NOTE: `actual` comes from `TripProvider.categoryTotals`; `planned` has no
/// data source yet (no per-category budget exists). Wire the chosen source
/// before mounting this in TripSummaryScreen.
class PlannedVsActualChart extends StatelessWidget {
  const PlannedVsActualChart({
    super.key,
    required this.categories,
    required this.symbol,
    this.height = 200,
  });

  final List<CategorySpend> categories;

  /// The trip's currency symbol (see lib/core/logic/currency.dart) — prefixes
  /// the value axis labels.
  final String symbol;
  final double height;

  static const Color _plannedColor = AppTheme.primary;
  static const Color _actualColor = AppTheme.primaryLight;

  @override
  Widget build(BuildContext context) {
    // Empty-category handling: drop categories the user hasn't touched at all,
    // so they don't eat an empty x-axis slot.
    final bars = [
      for (final c in categories)
        if (c.planned != 0 || c.actual != 0) c,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          // LayoutBuilder so the narrow-viewport fallback can decide, from the
          // real available width, whether the bars would be too thin to read
          // BEFORE handing the painter a slot it can't render usefully.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = bars.length;
              if (n == 0) {
                // Parent (_PlannedVsActualCard) owns the "no data" empty state;
                // if it ever hands us an all-empty list, draw nothing.
                return const SizedBox.shrink();
              }
              final maxVal = bars.fold<int>(
                  0, (m, b) => max(m, max(b.planned, b.actual)));
              final barW =
                  _PvaPainter.barWidthFor(constraints.maxWidth, n, maxVal);
              if (barW < _PvaPainter._minBarW) {
                return const _NarrowViewportFallback();
              }
              return CustomPaint(painter: _PvaPainter(bars, symbol));
            },
          ),
        ),
        const SizedBox(height: 12),
        const BarChartLegend(items: [
          ('Planned', _plannedColor),
          ('Actual', _actualColor),
        ]),
      ],
    );
  }
}

/// Shown when the viewport is too narrow for the grouped bars to render legibly.
class _NarrowViewportFallback extends StatelessWidget {
  const _NarrowViewportFallback();

  @override
  Widget build(BuildContext context) {
    // TODO(mobile-chart): render a tabular DataTable fallback (category rows,
    // planned/actual columns) instead of this "rotate device" placeholder — it
    // stays functional at any width. Its own design task; not blocking v1.
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Rotate your device to a wider view to compare planned vs. actual '
          'spending by category.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.lightMute,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PvaPainter extends CustomPainter {
  _PvaPainter(this.bars, this.symbol);

  final List<CategorySpend> bars;
  final String symbol;

  static const double _groupGap = 14; // horizontal gap between category groups
  // Intra-pair gap: 3px says "these two bars belong together" without letting
  // them merge into one shaded unit (Decision E, Option B — grouped pairs).
  // TODO(chart-density): mobile portrait × 8 categories is on the edge here;
  // revisit this gap (or the grouped layout) if the category list grows.
  static const double _barGap = 3;
  static const double _labelBand = 34; // reserved bottom strip for x labels
  static const double _headroom = 1.15; // 15% above tallest bar
  static const double _minBarPx = 1; // any nonzero value renders ≥ 1px
  static const double _minBarW = 4; // below this bar width the chart is illegible
  static const double _rotateBelowSlot = 60; // rotate x labels under this width
  static const double _axisGutter = 40; // left strip reserved for value labels
  static const int _axisMinValue = 100000; // hide the axis below ₫100K (noise)

  /// Bar width for the current geometry, shared with the widget's narrow-view
  /// guard so the two never disagree about when bars get too thin. Accounts for
  /// the axis gutter, which only exists once the max clears [_axisMinValue].
  static double barWidthFor(double totalWidth, int n, int maxVal) {
    final gutter = maxVal >= _axisMinValue ? _axisGutter : 0.0;
    final slot = (totalWidth - gutter) / n;
    return (slot - _groupGap - _barGap) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || bars.isEmpty) return;

    final chartH = size.height - _labelBand;
    if (chartH <= 0) return;
    final baseY = chartH;

    final maxVal = bars.fold<int>(
        0, (m, b) => max(m, max(b.planned, b.actual)));
    if (maxVal == 0) return; // Nothing to draw — parent renders the empty state.
    final top = maxVal * _headroom;

    final n = bars.length;

    // Axis only earns its gutter once the numbers are big enough to be worth
    // anchoring; below ₫100K the labels are more noise than signal.
    final showAxis = maxVal >= _axisMinValue;
    final gutter = showAxis ? _axisGutter : 0.0;
    final chartW = size.width - gutter;
    final slot = chartW / n;
    // Two bars + the inner gap live inside a slot, minus the between-group gap.
    final barW = (slot - _groupGap - _barGap) / 2;
    if (barW <= 0) return; // LayoutBuilder guards barW < 4; keep the divide safe.

    final rotate = slot < _rotateBelowSlot;

    // Reference axis behind the bars: hairlines + value labels at 50% and 100%
    // of the tallest value. Two anchors only — enough to answer "am I over on
    // any category?" at a glance without turning this into a data-analysis chart.
    if (showAxis) {
      _axis(canvas, gutter, size.width, baseY, chartH, top, maxVal);
    }

    for (var i = 0; i < n; i++) {
      final b = bars[i];
      final groupLeft = gutter + slot * i + _groupGap / 2;
      final actualLeft = groupLeft + barW + _barGap;

      // Planned bar (left), then actual bar (right). The actual bar turns danger
      // when it outruns a *real* budget (planned > 0) — the whole bar reddens,
      // not just the excess (Decision D). An unbudgeted category (planned == 0)
      // can't be "over," so it keeps the normal actual colour.
      _bar(canvas, groupLeft, barW, b.planned, chartH, baseY, top,
          PlannedVsActualChart._plannedColor);
      if (b.planned == 0) {
        // Hairline flat cap for zero-planned; asymmetric-but-intentional signal
        // that planned was explicitly zero, not missing. Planned colour (not a
        // neutral grey) so it reads as a planned value, not a chart axis part.
        canvas.drawRect(
          Rect.fromLTWH(groupLeft, baseY - 1.0, barW, 1.0),
          Paint()..color = PlannedVsActualChart._plannedColor,
        );
      }
      _bar(canvas, actualLeft, barW, b.actual, chartH, baseY, top,
          _actualBarColor(b.planned, b.actual));

      // Over-budget marker: a small danger triangle sitting just above the
      // actual bar, reinforcing the reddened bar. Same guard as the colour —
      // only for a genuine overspend against a nonzero budget.
      if (b.actual > b.planned && b.planned > 0) {
        _overageMarker(
            canvas, actualLeft + barW / 2, b.actual, chartH, baseY, top);
      }

      _label(canvas, gutter + slot * i + slot / 2, baseY, slot, b.label, rotate);
    }
  }

  // Whole actual bar reddens on a real overspend; unbudgeted categories stay the
  // normal actual colour.
  // TODO(overspend): flag "unbudgeted" categories (planned == 0, actual > 0)
  // differently if user testing shows the silent primary-light bar is confusing.
  Color _actualBarColor(int planned, int actual) {
    if (actual > planned && planned > 0) return AppTheme.danger;
    return PlannedVsActualChart._actualColor;
  }

  void _axis(Canvas canvas, double gutter, double width, double baseY,
      double chartH, double top, int maxVal) {
    // TODO(chart-axis): revisit the ₫100K threshold if a user reports a missing
    // axis on a genuine low-budget trip.
    final linePaint = Paint()
      ..color = AppTheme.lightBorder.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final frac in const [0.5, 1.0]) {
      final v = (maxVal * frac).round();
      final y = baseY - (v / top) * chartH;
      canvas.drawLine(Offset(gutter, y), Offset(width, y), linePaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '$symbol${Trip.formatVnd(v, short: true)}',
          style: const TextStyle(
            color: AppTheme.lightMute,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: gutter - 4);
      // Right-align the label against the gutter edge, vertically centred on
      // its line.
      tp.paint(canvas, Offset(gutter - 6 - tp.width, y - tp.height / 2));
    }
  }

  void _overageMarker(Canvas canvas, double centerX, int actual, double chartH,
      double baseY, double top) {
    // Downward-pointing (▼) so it reads as "attention here / over budget"
    // rather than the "growing / positive" grammar of an upward triangle
    // (Decision F). Filled + softly rounded, single danger colour, no shadow —
    // matches Explorife's filled-indicator visual language.
    final barTop = baseY - max((actual / top) * chartH, _minBarPx);
    final apexY = barTop - 4; // 4px gap so it floats above the bar, not on it
    const halfW = 4.0; // 8px base width overall
    // Flatter than equilateral so it reads as a warning marker (▽/⚠), not a
    // rotated play button. Height 5.6px at an 8px base ≈ 54° base angles.
    // NOTE: the review said "65° base angles → ~5.6px height," but at an 8px
    // base those don't correspond — 65° base angles give a ~8.6px-tall (taller,
    // NARROWER) triangle. The prose consistently wanted flatter+shorter, so I
    // built to the 5.6px height / flatter shape and dropped the "65°" label.
    // My call, veto-able — say the word and I'll switch to true 65° (taller).
    const triH = 5.6;
    final path = Path()
      ..moveTo(centerX - halfW, apexY - triH) // top-left
      ..lineTo(centerX + halfW, apexY - triH) // top-right
      ..lineTo(centerX, apexY) // apex points down
      ..close();
    canvas.drawPath(path, Paint()..color = AppTheme.danger);
    // Soften the corners: restroke the same outline with a round join.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.danger
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _bar(Canvas canvas, double left, double barW, int value, double chartH,
      double baseY, double top, Color color) {
    // No small-value threshold (unlike the donut): bars read linearly, so even
    // ₫1 gets a 1px nub rather than being hidden.
    if (value <= 0) return;
    final h = max((value / top) * chartH, _minBarPx);
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTRB(left, baseY - h, left + barW, baseY),
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }

  void _label(Canvas canvas, double centerX, double baseY, double slot,
      String text, bool rotate) {
    // Elide long category names to one line. Rotated labels get more diagonal
    // room than the flat slot, so widen the layout budget accordingly; either
    // way the ellipsis stops a long name from overrunning its neighbour.
    final maxWidth = rotate ? _labelBand * 1.5 : slot;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: AppTheme.lightMute,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    if (rotate) {
      // Rotate -45° with the label's right end (end of the word) anchored just
      // under the group centre, so text falls away to the lower-left toward the
      // tick without overrunning neighbours. (Kept the collision-safe right-end
      // anchor rather than a literal top-centre pin — my call, veto-able.)
      canvas.save();
      canvas.translate(centerX, baseY + 6);
      canvas.rotate(-pi / 4);
      tp.paint(canvas, Offset(-tp.width, 0));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(centerX - tp.width / 2, baseY + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _PvaPainter old) => true;
  // Repaint every build — a handful of bars, cheaper than diffing the list.
  // Matches the _BarsPainter / _ExpenseDonutPainter house pattern.
}

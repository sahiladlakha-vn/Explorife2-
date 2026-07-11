import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/trip.dart';
import 'chart_legend.dart';

/// Budget-by-category donut for the Trip Summary. Renders as two nested rings:
///
///   * Outer ring — the four budget buckets (stay / food / activity / transit)
///     from the trip's PLANNED distribution (`TripProvider.plannedByCategory`),
///     stroked clockwise from 12 o'clock, each slice's share labelled outside
///     the arc on a hairline connector.
///   * Inner ring — the ACTUAL logged spend (`TripProvider.categoryTotals`),
///     drawn thinner inside the hole at reduced alpha so it reads as a "shadow"
///     of the plan it fills. Rendered ONLY when some spend exists; on a fresh
///     trip the hole stays clean and the centre label ("₫5M / planned") does
///     the "no actuals yet" work (Decision A.i — a grey placeholder ring reads
///     as data-to-interpret, not empty state).
///
/// The centre label mode-switches: actuals total + "spent" once spend exists,
/// otherwise planned total + "planned". Over-budget categories
/// (actual > planned, planned > 0) get a downward danger triangle on the outer
/// ring slice — mirrors the bar chart's overage marker
/// (planned_vs_actual_chart.dart). A planned==0 category has no outer slice to
/// anchor a marker on, so it is skipped (matches the bar chart's guard).
///
/// Composition (per Refinement 2): the painter draws rings + arc labels +
/// connectors + markers only; the legend is a separate [ChartLegend] widget,
/// the centre total is a [FittedBox] child stacked over the paint, and the
/// two-ring caption ("Outer: planned · Inner: actuals") is a sibling [Text] —
/// none of that lives in `paint()`, and none of it couples into [ChartLegend].
///
/// Follows the CustomPainter house pattern in
/// trip_builder/widgets/summary_sidebar.dart: `size.isEmpty` guard,
/// `withValues(alpha:)`, `shouldRepaint => true` with a comment.
class ExpenseDonut extends StatelessWidget {
  const ExpenseDonut({
    super.key,
    required this.planned,
    required this.actual,
    this.diameter = 200,
  });

  /// The four zero-filled PLANNED buckets (VND) — the outer ring / colour key.
  final Map<String, int> planned;

  /// The four zero-filled ACTUAL buckets (VND) — the inner ring. All-zero on a
  /// fresh trip, in which case the inner ring is not drawn.
  final Map<String, int> actual;

  /// Bumped 180→200 (relief (i)): the inner ring steals the centre hole the
  /// label uses, so the extra diameter keeps both ring strokes and the label
  /// legible rather than shrinking the label to fit a 180px hole.
  final double diameter;

  // Fixed bucket order so slice colours and the legend stay stable regardless
  // of the incoming maps' iteration order.
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
    final plannedSlices = [
      for (final k in _order)
        _DonutSlice(_labels[k]!, planned[k] ?? 0, _colors[k]!),
    ];
    final actualSlices = [
      for (final k in _order)
        _DonutSlice(_labels[k]!, actual[k] ?? 0, _colors[k]!),
    ];
    final plannedTotal = plannedSlices.fold<int>(0, (s, e) => s + e.value);
    final actualTotal = actualSlices.fold<int>(0, (s, e) => s + e.value);

    // Mode-switched centre label: actuals win once spend exists, otherwise the
    // plan. One label at a time — never both, never ambiguous.
    final hasActual = actualTotal > 0;
    final centreValue = hasActual ? actualTotal : plannedTotal;
    final centreCaption = hasActual ? 'spent' : 'planned';

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
                painter: _ExpenseDonutPainter(plannedSlices, actualSlices),
              ),
              // Centre total. FittedBox scales down so ₫999,999,999 still fits
              // the ring hole at small viewport sizes. Padding keeps the text
              // inside the hole rather than overrunning the ring. Rendered as a
              // Stack child AFTER the CustomPaint, so it always composites on
              // top of the reduced-alpha inner ring — the label never loses
              // contrast to the ring behind it (Refinement 1).
              // TODO(label-transition): the mode-switch ₫planned→₫spent can
              // re-scale the FittedBox on the first actuals write; consider a
              // fixed-scale label if the jump reads as jarring.
              Padding(
                padding: EdgeInsets.all(diameter * 0.30),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₫${Trip.formatVnd(centreValue, short: true)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        centreCaption,
                        style: const TextStyle(
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
        // Colour key comes from the PLANNED distribution (the outer ring / the
        // always-present series). Arc labels are % only per Decision A;
        // see docs/audits/explorife-triage-audit-2026-07-04.md
        ChartLegend(
          items: [
            for (final s in plannedSlices)
              if (s.value > 0) (s.label, s.color),
          ],
        ),
        // Two-ring caption — only meaningful once the inner ring is actually
        // drawn (Refinement 2). Sits below the whole legend Wrap (Column
        // composition), so it stays under a multi-row chip stack at narrow
        // widths rather than attaching to one chip row. No bullet prefix.
        if (hasActual) ...[
          const SizedBox(height: 6),
          const Text(
            'Outer: planned · Inner: actuals',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
  _ExpenseDonutPainter(this.planned, this.actual);

  /// Same length, same `_order` index alignment — zipped for overage checks.
  final List<_DonutSlice> planned;
  final List<_DonutSlice> actual;

  static const double _ringThickness = 16; // outer (planned) ring
  static const double _innerThickness = 8; // inner (actuals) ring, ~half
  static const double _ringGap = 4; // breathing space between the two rings
  static const double _labelGutter = 46; // room outside the ring for labels
  static const double _connector = 8; // hairline length from arc edge to label
  static const double _minLabelFraction = 0.03; // hide labels under 3%
  static const double _innerAlpha = 0.7; // inner ring reads as a "shadow"

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Reserve the gutter so outside labels aren't clipped by the paint bounds.
    final ringRadius = min(size.width, size.height) / 2 - _labelGutter;
    if (ringRadius <= 0) return;

    final plannedTotal = planned.fold<int>(0, (s, e) => s + e.value);

    // Degenerate: no plan at all — faint placeholder ring, no labels. Defensive
    // only; the composing card gates on plannedTotal > 0 and the seed
    // guarantees a nonzero plan, so this should never render in practice.
    if (plannedTotal == 0) {
      canvas.drawCircle(
        center,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringThickness
          ..strokeCap = StrokeCap.butt
          ..color = AppTheme.divider,
      );
      return;
    }

    // --- Outer ring: PLANNED distribution -----------------------------------
    final outerRect = Rect.fromCircle(center: center, radius: ringRadius);
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringThickness
      ..strokeCap = StrokeCap.butt;

    const startAngle = -pi / 2; // 12 o'clock
    var angle = startAngle;
    // Capture each slice's mid-angle so the overage markers below can anchor to
    // the outer ring. null == slice not drawn (planned value 0) → no anchor.
    final midAngles = List<double?>.filled(planned.length, null);

    for (var i = 0; i < planned.length; i++) {
      final s = planned[i];
      if (s.value == 0) continue; // skip empty buckets entirely
      final frac = s.value / plannedTotal;
      final sweep = frac * 2 * pi; // clockwise (positive sweep, y-down)
      outerPaint.color = s.color;
      canvas.drawArc(outerRect, angle, sweep, false, outerPaint);
      final mid = angle + sweep / 2;
      midAngles[i] = mid;
      if (frac >= _minLabelFraction) {
        _paintLabel(canvas, center, ringRadius, mid, frac);
      }
      angle += sweep;
    }

    // --- Inner ring: ACTUAL spend (only when spend exists) ------------------
    final actualTotal = actual.fold<int>(0, (s, e) => s + e.value);
    if (actualTotal > 0) {
      // Nest inside the hole: outer inner-edge (ringRadius - t/2), then a gap,
      // then this ring's own half-thickness.
      final innerRadius =
          ringRadius - _ringThickness / 2 - _ringGap - _innerThickness / 2;
      if (innerRadius > 0) {
        final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
        final innerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _innerThickness
          ..strokeCap = StrokeCap.butt;
        var a = startAngle;
        for (final s in actual) {
          if (s.value == 0) continue;
          final sweep = (s.value / actualTotal) * 2 * pi;
          // Same slice colour as the plan, muted so the two rings visually
          // stack. TODO(donut-alpha): if the centre label loses contrast where
          // the inner ring passes behind it, drop to 0.5 — verified on the dark
          // theme at write-time (label composites on top, so contrast holds).
          innerPaint.color = s.color.withValues(alpha: _innerAlpha);
          canvas.drawArc(innerRect, a, sweep, false, innerPaint);
          a += sweep;
        }
      }
    }

    // --- Over-budget markers on the OUTER ring ------------------------------
    // Per-category (Decision B.ii): a slice is over iff actual > planned AND
    // planned > 0 — the marker anchors on the planned slice's mid-angle, which
    // only exists when that slice was drawn. Mark ALL offenders (Decision
    // C.ii); a chart full of triangles is itself the "overspending across the
    // board" signal.
    // TODO(donut-density): if user testing shows 4+ triangles on one chart
    // looks cluttered, consider aggregating into a single marker with a count
    // badge.
    for (var i = 0; i < planned.length; i++) {
      final mid = midAngles[i];
      if (mid == null) continue; // planned == 0 → nothing to anchor on
      if (actual[i].value > planned[i].value) {
        final dir = Offset(cos(mid), sin(mid));
        _overageMarker(canvas, center + dir * ringRadius);
      }
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

  /// Downward-pointing (▼) danger triangle centred on [at]. Screen-axis-aligned
  /// (not rotated to the ring's radial normal) so it reads as the same warning
  /// glyph as the bar chart's overage marker rather than a tilted arbitrary
  /// shape. Geometry copied from planned_vs_actual_chart.dart `_overageMarker`:
  /// 8px base, 5.6px tall, filled + round-join restroke.
  void _overageMarker(Canvas canvas, Offset at) {
    const halfW = 4.0; // 8px base
    const triH = 5.6; // flatter than equilateral → reads as ▽/⚠
    final topY = at.dy - triH / 2;
    final apexY = at.dy + triH / 2;
    final path = Path()
      ..moveTo(at.dx - halfW, topY) // top-left
      ..lineTo(at.dx + halfW, topY) // top-right
      ..lineTo(at.dx, apexY) // apex points down
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

  @override
  bool shouldRepaint(covariant _ExpenseDonutPainter old) => true;
  // Repaint every build — cheap for ≤6 categories and avoids memoization
  // gymnastics. Matches the _BarsPainter / _RoutePainter house pattern.
}

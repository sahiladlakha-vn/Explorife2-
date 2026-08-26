import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/logic/currency.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../widgets/budget_status.dart';

/// Right pane: an at-a-glance summary of the trip and the active day. Four
/// visualizations at mixed scope — route schematic (active day), budget bar +
/// category breakdown + spend-by-day (whole trip). [collapsed] renders the
/// mobile peek (a day-status line + trip-budget number) that expands into the
/// same [_SidebarBody] the desktop pane shows — one body, two hosts, so the two
/// can never drift.
class SummarySidebar extends StatelessWidget {
  const SummarySidebar({
    super.key,
    required this.tripId,
    required this.activeDay,
    this.collapsed = false,
  });

  final String tripId;
  final int activeDay;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return _MobilePeek(tripId: tripId, activeDay: activeDay);
    }
    return Container(
      color: AppTheme.lightCard,
      child: _SidebarBody(tripId: tripId, activeDay: activeDay),
    );
  }
}

/// The shared summary body — rendered directly in the desktop pane and inside
/// the expanded mobile sheet. Takes an optional [scrollController] so the sheet
/// can drive its own scroll.
class _SidebarBody extends StatelessWidget {
  const _SidebarBody({
    required this.tripId,
    required this.activeDay,
    this.scrollController,
  });

  final String tripId;
  final int activeDay;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    // TODO(perf): categoryTotals / dayTotal / stopsForDay each return a fresh
    // value per call, so this whole-body watch rebuilds on every trip mutation.
    // That's the intent here — it's a live summary — and cheap at this scale.
    final p = context.watch<TripProvider>();
    final gems = context.watch<GemProvider>().allGems;

    final trip = p.tripById(tripId);
    if (trip == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No trip loaded.',
              style: TextStyle(color: AppTheme.lightMute)),
        ),
      );
    }

    final symbol = currencyFor(trip.currency).symbol;
    final dayCount = trip.nights + 1;
    final safeDay = activeDay.clamp(1, dayCount);
    final totalSpent = p.totalSpent(tripId);
    final totals = p.categoryTotals(tripId);
    final dayTotals = [for (var d = 1; d <= dayCount; d++) p.dayTotal(tripId, d)];

    // Active-day route: keep EVERY coorded stop in slot→sortOrder order (a
    // two-stop morning draws two points). Custom/uncoorded stops fall to the
    // "Also today" list so the geometry stays honest.
    Gem? resolveGem(String id) =>
        gems.cast<Gem?>().firstWhere((g) => g?.id == id, orElse: () => null);
    final points = <({double lat, double lng})>[];
    final alsoToday = <String>[];
    for (final s in p.stopsForDay(tripId, safeDay)) {
      final gem = s.isCustom ? null : resolveGem(s.gemId!);
      if (gem != null && gem.hasCoords) {
        points.add((lat: gem.latitude!, lng: gem.longitude!));
      } else {
        alsoToday.add(_alsoLabel(s, gem));
      }
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // TODO(map): flutter_map is a dependency — swap this schematic for a
        // full-screen route detail view (zoom/pan/street context) if we ever
        // want one. For a 320px orientation glance, the schematic wins.
        _Section(
          title: 'Route · Day $safeDay',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RouteSchematic(points: points),
              if (alsoToday.isNotEmpty) _AlsoToday(titles: alsoToday),
            ],
          ),
        ),
        _Section(
          title: 'Budget',
          child: _BudgetBar(
              spent: totalSpent, budgetVnd: trip.budgetVnd, symbol: symbol),
        ),
        _Section(
          title: 'By category',
          child: _CategoryBreakdown(totals: totals, symbol: symbol),
        ),
        _Section(
          title: 'By day',
          child: _SpendByDayChart(dayTotals: dayTotals, activeDay: safeDay),
        ),
      ],
    );
  }
}

// --- Section chrome -------------------------------------------------------

/// A titled block. Uniform label styling + spacing for every summary section.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.lightMute,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// --- Route schematic ------------------------------------------------------

/// Aspect-preserving route map for the active day. Dashed empty state when no
/// stop has coordinates; a single centered pin for one; the routed path for 2+.
class _RouteSchematic extends StatelessWidget {
  const _RouteSchematic({required this.points});

  final List<({double lat, double lng})> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const _EmptyRoute();
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: CustomPaint(painter: _RoutePainter(points), size: Size.infinite),
    );
  }
}

/// Placeholder when the active day has nothing mappable (all custom / uncoorded).
class _EmptyRoute extends StatelessWidget {
  const _EmptyRoute();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: const Text('No mappable stops today',
          style: TextStyle(color: AppTheme.lightMute, fontSize: 12)),
    );
  }
}

/// Draws the day's stops as numbered dots joined in order. Longitude is scaled
/// by cos(lat) so east–west and north–south read to the same ground scale —
/// without it, a tight neighborhood cluster would look like a cross-city sprawl.
class _RoutePainter extends CustomPainter {
  _RoutePainter(this.pts);

  final List<({double lat, double lng})> pts;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return; // zero-width parent during a layout transition

    const pad = 24.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;

    if (pts.length == 1) {
      _dot(canvas, Offset(size.width / 2, size.height / 2), '1');
      return;
    }

    final lats = pts.map((p) => p.lat);
    final lngs = pts.map((p) => p.lng);
    final minLat = lats.reduce(min), maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min), maxLng = lngs.reduce(max);
    final midLatRad = ((minLat + maxLat) / 2) * (pi / 180);

    // Ground-distance spans; guard zero spans (all stops share a coordinate).
    final spanX = max((maxLng - minLng).abs() * cos(midLatRad), 1e-9);
    final spanY = max((maxLat - minLat).abs(), 1e-9);
    final scale = min(w / spanX, h / spanY); // one scale → preserve aspect
    final drawW = spanX * scale, drawH = spanY * scale;
    final ox = pad + (w - drawW) / 2, oy = pad + (h - drawH) / 2;

    Offset project(({double lat, double lng}) p) {
      final gx = (p.lng - minLng) * cos(midLatRad) * scale;
      final gy = (p.lat - minLat) * scale;
      return Offset(ox + gx, oy + drawH - gy); // invert Y → north up
    }

    final offsets = [for (final p in pts) project(p)];

    final line = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);

    for (var i = 0; i < offsets.length; i++) {
      _dot(canvas, offsets[i], '${i + 1}');
    }
  }

  void _dot(Canvas canvas, Offset c, String label) {
    canvas.drawCircle(c, 11, Paint()..color = AppTheme.primary);
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  // Repaint every build — cheap for ≤5 dots and avoids memoization gymnastics.
  @override
  bool shouldRepaint(_RoutePainter old) => true;
}

/// Lists the day's non-mappable stops (custom entries, or gems without coords)
/// so they're accounted for without breaking the schematic's geometry.
class _AlsoToday extends StatelessWidget {
  const _AlsoToday({required this.titles});

  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Also today',
              style: TextStyle(
                  color: AppTheme.lightMute,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final t in titles)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $t',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.lightInk, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// --- Budget bar -----------------------------------------------------------

/// Whole-trip budget progress. Shares [BudgetStatus] with the header pill: same
/// thresholds, same accent, different shape. Fill is clamped so an over-budget
/// trip pins full-red rather than overflowing the track.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar(
      {required this.spent, required this.budgetVnd, required this.symbol});

  final int spent;
  final int budgetVnd;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: budgetVnd);
    final fill = (status.pct / 100).clamp(0.0, 1.0);
    final remaining = budgetVnd - spent;

    final tail = status.over
        ? '$symbol${Trip.formatVnd(-remaining, short: true)} over'
        : '$symbol${Trip.formatVnd(remaining, short: true)} left';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('$symbol${Trip.formatVnd(spent, short: true)}',
                style: TextStyle(
                    color: status.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('of $symbol${Trip.formatVnd(budgetVnd, short: true)}',
                  style: const TextStyle(
                      color: AppTheme.lightMute, fontSize: 12)),
            ),
            const Spacer(),
            Text('${status.pct.round()}%',
                style: TextStyle(
                    color: status.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Container(height: 8, color: AppTheme.lightCard),
              FractionallySizedBox(
                widthFactor: fill,
                child: Container(
                  height: 8,
                  color: status.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(tail,
            style: TextStyle(
                color: status.over ? AppTheme.danger : AppTheme.lightMute,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// --- Category breakdown ---------------------------------------------------

/// Horizontal bars, one per budget bucket, normalized to the largest current
/// total so relative magnitude reads at a glance ("stays dominate"). Fixed order
/// matches categoryTotals' stable key order.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.totals, required this.symbol});

  final Map<String, int> totals;
  final String symbol;

  static const _rows = [
    ('stay', 'Stays', AppTheme.primary),
    ('food', 'Food', AppTheme.teal),
    ('activity', 'Activities', AppTheme.purple),
    ('transit', 'Transit', AppTheme.pink),
  ];

  @override
  Widget build(BuildContext context) {
    final maxVal =
        totals.values.fold<int>(0, (m, v) => v > m ? v : m); // largest bucket

    return Column(
      children: [
        for (final (key, label, color) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CategoryRow(
              label: label,
              color: color,
              value: totals[key] ?? 0,
              symbol: symbol,
              // Empty state (no spend anywhere) → all bars flat, not a crash.
              fraction: maxVal == 0 ? 0.0 : (totals[key] ?? 0) / maxVal,
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.color,
    required this.value,
    required this.symbol,
    required this.fraction,
  });

  final String label;
  final Color color;
  final int value;
  final String symbol;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(label,
              style: const TextStyle(
                  color: AppTheme.lightInk, fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              children: [
                Container(height: 10, color: AppTheme.lightCard),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(height: 10, color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text('$symbol${Trip.formatVnd(value, short: true)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: AppTheme.lightMute,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// --- Spend-by-day chart ---------------------------------------------------

/// Per-day spend as a small bar chart, active day highlighted. Bars are painted;
/// day-number labels ride a matching Expanded row beneath so they stay aligned
/// without TextPainter fuss.
class _SpendByDayChart extends StatelessWidget {
  const _SpendByDayChart({required this.dayTotals, required this.activeDay});

  final List<int> dayTotals;
  final int activeDay;

  @override
  Widget build(BuildContext context) {
    // TODO(long-trips): horizontal scroll when day count exceeds sidebar width.
    // At 3–10 days (the real distribution) fixed bars are comfortably wide.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 96,
          child: CustomPaint(
            painter:
                _BarsPainter(dayTotals: dayTotals, activeIndex: activeDay - 1),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < dayTotals.length; i++)
              Expanded(
                child: Text('${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: i == activeDay - 1
                            ? AppTheme.primary
                            : AppTheme.lightMute,
                        fontSize: 10,
                        fontWeight: i == activeDay - 1
                            ? FontWeight.w800
                            : FontWeight.w500)),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.dayTotals, required this.activeIndex});

  final List<int> dayTotals;
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || dayTotals.isEmpty) return;

    final maxVal = dayTotals.fold<int>(0, (m, v) => v > m ? v : m);
    final n = dayTotals.length;
    final slot = size.width / n;
    const barInset = 4.0; // gap on each side of a bar within its slot
    final baseY = size.height;

    for (var i = 0; i < n; i++) {
      final v = dayTotals[i];
      final barH = maxVal == 0 ? 0.0 : (v / maxVal) * (size.height - 4);
      final left = slot * i + barInset;
      final right = slot * (i + 1) - barInset;
      final active = i == activeIndex;
      final paint = Paint()
        ..color = active
            ? AppTheme.primary
            : AppTheme.primary.withValues(alpha: 0.25);
      // Minimum 2px nub so an empty day still reads as "a day", not a gap.
      final top = baseY - max(barH, v == 0 ? 0.0 : 2.0);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(left, top, right, baseY),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  // Repaint every build — a handful of bars, cheaper than diffing the list.
  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

// --- Mobile peek ----------------------------------------------------------

/// Collapsed mobile summary: a day-status line (active-day scope) + the trip
/// budget number (trip scope) + an expand affordance. Two scopes on purpose —
/// the ambient line tracks the day you're looking at; the budget is the constant
/// reference. Tapping expands the full [_SidebarBody] in a draggable sheet.
class _MobilePeek extends StatelessWidget {
  const _MobilePeek({required this.tripId, required this.activeDay});

  final String tripId;
  final int activeDay;

  void _expand(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.lightMute,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Expanded(
                child: _SidebarBody(
                  tripId: tripId,
                  activeDay: activeDay,
                  scrollController: controller,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TripProvider>();
    final trip = p.tripById(tripId);
    final symbol = currencyFor(trip?.currency).symbol;
    final safeDay =
        trip == null ? activeDay : activeDay.clamp(1, trip.nights + 1);
    final status = BudgetStatus.of(
        spent: p.totalSpent(tripId), budgetVnd: trip?.budgetVnd ?? 0);

    return Material(
      color: AppTheme.lightCard,
      child: InkWell(
        onTap: () => _expand(context),
        child: Container(
          height: 120,
          // Horizontal padding matches the wizard's bottom bar rhythm (was
          // 16). Not adding the wizard's safe-area bottom inset here too —
          // this bar has a fixed 120px height (_kSummaryPeekHeight), and
          // eating into that with a safe-area inset would compress/clip its
          // two text rows on devices with a home-indicator inset.
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.lightBorder)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_dayStatusLine(p, tripId, safeDay, symbol),
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 13)),
                  ),
                  const Icon(Icons.keyboard_arrow_up,
                      color: AppTheme.lightMute),
                ],
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text:
                        '$symbol${Trip.formatVnd(p.totalSpent(tripId), short: true)}',
                    style: TextStyle(
                        color: status.accent,
                        fontSize: 20,
                        fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text:
                        ' of $symbol${Trip.formatVnd(trip?.budgetVnd ?? 0, short: true)}',
                    style: const TextStyle(
                        color: AppTheme.lightMute, fontSize: 13),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Helpers --------------------------------------------------------------

/// Active-day status line: "3 stops · ₫1.2M today". Shared so the peek and any
/// future day-status surface phrase it identically.
String _dayStatusLine(TripProvider p, String tripId, int day, String symbol) {
  final n = p.stopsForDay(tripId, day).length;
  final stops = n == 1 ? '1 stop' : '$n stops';
  return '$stops · $symbol${Trip.formatVnd(p.dayTotal(tripId, day), short: true)} today';
}

/// Label for a non-mappable stop in the "Also today" list.
String _alsoLabel(TripStop s, Gem? gem) {
  if (s.isCustom) return s.customTitle ?? 'Custom stop';
  return gem?.gemName ?? 'Gem unavailable';
}

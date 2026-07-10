import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/budget_status.dart';
import 'widgets/checklist_card.dart';
import 'widgets/expense_donut.dart';
import 'widgets/planned_vs_actual_chart.dart';

/// Trip Summary — the trip's dashboard and canonical landing (`/trips/:id`).
///
/// Subscriber, not owner: no local state. Mirrors [TripBuilderScreen]'s
/// loaded / loading / error / not-found state machine so a deep-link to a trip
/// behaves identically on both surfaces.
///
/// Card order encodes a narrative arc (approved in step 8): temporal anchor →
/// spend total → per-category deltas → per-category composition → tasks →
/// auxiliary reference. Each card answers the question the previous one raised.
/// Every card selects its own narrow slice; this screen is pure composition.
class TripSummaryScreen extends StatelessWidget {
  const TripSummaryScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    // Narrow slices — the screen shell only rebuilds on the state transitions it
    // owns; each card re-subscribes to its own data below.
    final trip = context.select<TripProvider, Trip?>((p) => p.tripById(tripId));
    final isLoading = context.select<TripProvider, bool>((p) => p.isLoading);
    final error = context.select<TripProvider, String?>((p) => p.error);

    // Trip present wins: transient mutation errors must not blow away a loaded
    // summary. Absent → loading / error / 404, same precedence as the builder.
    if (trip != null) return _loaded(context, trip);
    if (isLoading) return _skeleton(context);
    if (error != null) return _errorState(context, error);
    return _notFound(context);
  }

  // ---- Loaded: single vertical scroll, mobile-first, capped reading width. ----
  Widget _loaded(BuildContext context, Trip trip) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _appBar(context, title: trip.displayName),
      body: SafeArea(
        top: false,
        child: Center(
          // Cap the column so the cards don't stretch to tablet/desktop widths;
          // the Summary is a reading surface, not a workspace like the builder.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _CountdownCard(tripId: tripId),
                const SizedBox(height: 12),
                _BudgetSnapshotCard(tripId: tripId),
                const SizedBox(height: 12),
                _PlannedVsActualCard(tripId: tripId),
                const SizedBox(height: 12),
                _ExpenseDonutCard(tripId: tripId),
                const SizedBox(height: 12),
                ChecklistCard(tripId: tripId),
                const SizedBox(height: 12),
                _CurrencyCard(tripId: tripId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Loading: card-stack skeleton so the layout doesn't jump on first paint.
  Widget _skeleton(BuildContext context) {
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
        );
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _appBar(context),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [block(88), block(120), block(240), block(240)],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Error: raw message kept as a clipped diagnostic breadcrumb. ----
  Widget _errorState(BuildContext context, String message) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _appBar(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppTheme.textSecondary, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load this trip.",
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
              const SizedBox(height: 6),
              Text(message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.read<TripProvider>().init(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Not found: trip missing after a completed load. ----
  Widget _notFound(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _appBar(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined,
                  color: AppTheme.textSecondary, size: 40),
              const SizedBox(height: 12),
              const Text("This trip doesn't exist or isn't yours.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/profile'),
                child: const Text('Go to trips'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _appBar(BuildContext context, {String? title}) => AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        title: title == null
            ? null
            : Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
        // TODO(tab-deeplink): target the Trips tab once it's deep-linkable.
        leading: BackButton(
            color: AppTheme.textPrimary,
            onPressed: () => context.go('/profile')),
      );
}

// ===========================================================================
// Shared card chrome. One place owns the dark surface / radius / padding /
// title so every Summary card reads with the same weight and rhythm.
//
// Composition convention: the thin private wrapper cards in this file
// (_CountdownCard, _BudgetSnapshotCard, _CurrencyCard, and the wrappers around
// ExpenseDonut / PlannedVsActualChart) wrap their body in this chrome. The
// heavy self-contained widgets live in their own files under widgets/ and carry
// their own chrome — [ChecklistCard] (Container + "Checklist" title + section
// grouping) and [ExpenseDonut] (ring + legend). So ChecklistCard is dropped in
// bare and the donut is wrapped only for a title (see _ExpenseDonutCard).
// ===========================================================================
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

Widget _emptyLine(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    );

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _fmtDate(DateTime d) => '${_monthAbbr[d.month - 1]} ${d.day}, ${d.year}';

// ===========================================================================
// Countdown — temporal anchor. Reads the trip's dates and a live days-to-go.
// ===========================================================================
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    // Select the whole Trip (not a slice) — a rare mid-view deletion resolves to
    // shrink rather than a null-bang. Trip identity swaps only on edit → low
    // churn, so this isn't an over-broad subscription in practice.
    final trip = context.select<TripProvider, Trip?>((p) => p.tripById(tripId));
    if (trip == null) return const SizedBox.shrink();

    final daysUntil = trip.daysUntilStart;
    final endInDays = trip.endDate.difference(DateTime.now()).inDays;

    final String headline;
    final String sub;
    if (daysUntil > 1) {
      headline = '$daysUntil days to go';
      sub = 'Departs ${_fmtDate(trip.startDate)}';
    } else if (daysUntil == 1) {
      headline = 'Tomorrow';
      sub = 'Departs ${_fmtDate(trip.startDate)}';
    } else if (daysUntil == 0) {
      headline = 'Departs today';
      sub = _fmtDate(trip.startDate);
    } else if (endInDays >= 0) {
      headline = 'Trip in progress';
      sub = 'Through ${_fmtDate(trip.endDate)}';
    } else {
      headline = 'Trip complete';
      sub = '${_fmtDate(trip.startDate)} – ${_fmtDate(trip.endDate)}';
    }

    return _SummaryCard(
      title: 'Countdown',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline,
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Budget snapshot — total spend vs budget. Reuses [BudgetStatus] so over-budget
// behavior matches the builder header pill and sidebar bar exactly (one state
// machine, three visuals). Per Catch 1: the accent color spans BOTH the ₫amount
// and the "N% used" line so the status block reads as one semantic unit.
// ===========================================================================
class _BudgetSnapshotCard extends StatelessWidget {
  const _BudgetSnapshotCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    // Record slice → value equality, so this rebuilds only when spent or budget
    // actually changes (not on every unrelated provider notify).
    final (spent, budget) = context.select<TripProvider, (int, int)>((p) {
      final t = p.tripById(tripId);
      return (p.totalSpent(tripId), t?.budgetVnd ?? 0);
    });

    final status = BudgetStatus.of(spent: spent, budgetVnd: budget);
    final fill = (status.pct / 100).clamp(0.0, 1.0);
    final remaining = budget - spent;
    final tail = status.over
        ? '₫${Trip.formatVnd(-remaining, short: true)} over'
        : '₫${Trip.formatVnd(remaining, short: true)} left';

    return _SummaryCard(
      title: 'Budget',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('₫${Trip.formatVnd(spent, short: true)}',
                  style: TextStyle(
                      color: status.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('of ₫${Trip.formatVnd(budget, short: true)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              // Catch 1: percentage carries the accent too — a muted % beside a
              // red number would be a mixed signal.
              Text('${status.pct.round()}% used',
                  style: TextStyle(
                      color: status.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 8, color: AppTheme.surface2),
                FractionallySizedBox(
                  widthFactor: fill,
                  child: Container(height: 8, color: status.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(tail,
              style: TextStyle(
                  color:
                      status.over ? AppTheme.danger : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Planned vs actual — per-category deltas. Zips plannedByCategory (seeded vibe
// defaults) with categoryTotals (actual spend) into the chart's CategorySpend
// contract. Labels match the donut (Stay/Food/Do/Move) so the two spend cards
// read consistently.
// ===========================================================================
class _PlannedVsActualCard extends StatelessWidget {
  const _PlannedVsActualCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    // Eight-int record slice (planned×4, actual×4) → value equality, so the two
    // fresh Maps the provider returns don't force a rebuild every notify.
    final v = context.select<TripProvider,
        (int, int, int, int, int, int, int, int)>((p) {
      final pl = p.plannedByCategory(tripId);
      final ac = p.categoryTotals(tripId);
      return (
        pl['stay'] ?? 0,
        pl['food'] ?? 0,
        pl['activity'] ?? 0,
        pl['transit'] ?? 0,
        ac['stay'] ?? 0,
        ac['food'] ?? 0,
        ac['activity'] ?? 0,
        ac['transit'] ?? 0,
      );
    });

    final cats = <CategorySpend>[
      CategorySpend('Stay', v.$1, v.$5),
      CategorySpend('Food', v.$2, v.$6),
      CategorySpend('Do', v.$3, v.$7),
      CategorySpend('Move', v.$4, v.$8),
    ];
    final anyData = cats.any((c) => c.planned != 0 || c.actual != 0);

    return _SummaryCard(
      title: 'Planned vs actual',
      // Whole-card empty state: with neither a budget nor any spend the grouped
      // bars would be an empty axis. The chart also self-guards (drops zero
      // pairs, mobile-narrow fallback), so this only handles the all-zero case.
      child: anyData
          ? PlannedVsActualChart(categories: cats)
          : _emptyLine('No budget or spending to compare yet.'),
    );
  }
}

// ===========================================================================
// Expense donut — per-category composition. [ExpenseDonut] already composes its
// own ring + centre total + legend (arc labels % only per Decision A; the
// "composed with legend" assertion lives at that seam inside expense_donut.dart),
// so this card is thin chrome + a whole-card empty state.
// ===========================================================================
class _ExpenseDonutCard extends StatelessWidget {
  const _ExpenseDonutCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final t = context.select<TripProvider, (int, int, int, int)>((p) {
      final m = p.categoryTotals(tripId);
      return (m['stay'] ?? 0, m['food'] ?? 0, m['activity'] ?? 0,
          m['transit'] ?? 0);
    });
    final total = t.$1 + t.$2 + t.$3 + t.$4;
    final totals = {
      'stay': t.$1,
      'food': t.$2,
      'activity': t.$3,
      'transit': t.$4,
    };

    return _SummaryCard(
      title: "Where it's going",
      child: total == 0
          ? _emptyLine('No spending logged yet.')
          : Center(child: ExpenseDonut(categoryTotals: totals)),
    );
  }
}

// ===========================================================================
// Reference rates — auxiliary. Built net-new (there was no prior CurrencyWidget
// to "reverse"; grep confirmed no currency/FX code existed). Semantic per Catch
// 2, oriented for a Vietnam-first audience: a VND trip needs no conversion; a
// foreign-currency trip shows "1 X = ₫… VND" with a USD line for global
// reference.
//
// DORMANT TODAY: the app is single-currency (Trip.currency defaults to 'VND'
// and is treated as identity), so this branch shrinks for every current trip.
// It's a forward seam for when multi-currency trips exist — which is also why
// the placeholder rates below never reach a user.
// ===========================================================================
class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.tripId});

  final String tripId;

  // TODO(rates): replace with live rates via a server-side proxy. STATIC
  // PLACEHOLDERS — wrong by definition, kept only so the dormant widget renders
  // a shape. Never shown today (see class doc), so the staleness can't mislead.
  static const Map<String, int> _placeholderVndPer = {
    'USD': 25400,
    'EUR': 27600,
    'JPY': 170,
    'KRW': 19,
    'THB': 720,
    'SGD': 18800,
  };

  @override
  Widget build(BuildContext context) {
    final currency = context
        .select<TripProvider, String?>((p) => p.tripById(tripId)?.currency);

    // VND trip → skip: the user already knows what VND is (Catch 2 reversal).
    if (currency == null || currency == 'VND') return const SizedBox.shrink();

    final vndPer = _placeholderVndPer[currency];
    // Unknown currency → no sensible rate to show; stay silent rather than guess.
    if (vndPer == null) return const SizedBox.shrink();

    final usdPer = _placeholderVndPer['USD']!;
    final inUsd = vndPer / usdPer;

    return _SummaryCard(
      title: 'Reference rates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1 $currency = ₫${Trip.formatVnd(vndPer)}',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          // Row 2 is redundant when the trip currency IS USD — hide it.
          if (currency != 'USD') ...[
            const SizedBox(height: 4),
            Text('≈ \$${inUsd.toStringAsFixed(2)} USD',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/budget_status.dart';
import 'widgets/discovery_panel.dart';
import 'widgets/itinerary_canvas.dart';
import 'widgets/summary_sidebar.dart';

/// Full-screen 3-pane Trip Builder. Subscriber, not owner: the only local state
/// is [_activeDay]; trips/stops live on TripProvider. Dark colorway throughout.
class TripBuilderScreen extends StatefulWidget {
  const TripBuilderScreen({super.key, required this.tripId});
  final String tripId;

  @override
  State<TripBuilderScreen> createState() => _TripBuilderScreenState();
}

class _TripBuilderScreenState extends State<TripBuilderScreen> {
  int _activeDay = 1;
  void _onDayChanged(int day) => setState(() => _activeDay = day);

  @override
  Widget build(BuildContext context) {
    // Narrow slices so the shell only rebuilds on the transitions it cares about.
    final trip = context
        .select<TripProvider, Trip?>((p) => p.tripById(widget.tripId));
    final isLoading = context.select<TripProvider, bool>((p) => p.isLoading);
    final error = context.select<TripProvider, String?>((p) => p.error);

    // Trip present wins: transient mutation errors surface via pane snackbars,
    // they must not blow the loaded builder away. Absent → loading/error/404.
    if (trip != null) return _loaded(context, trip);
    if (isLoading) return _skeleton();
    if (error != null) return _errorState(context, error);
    return _notFound(context);
  }

  // ---- State 4: loaded → responsive 3-pane ----
  Widget _loaded(BuildContext context, Trip trip) {
    // Computed once so the header's height/layout and the body breakpoints agree
    // on a single source of truth (width is identical either side of the app bar,
    // so there's no mismatch to reconcile).
    final isMobile = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _TripBuilderHeader(tripId: widget.tripId, isMobile: isMobile),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w >= 900) {
            final left = w >= 1100 ? 280.0 : 240.0;
            final right = w >= 1100 ? 320.0 : 280.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                    width: left, child: DiscoveryPanel(tripId: widget.tripId)),
                const VerticalDivider(width: 1, color: AppTheme.divider),
                Expanded(
                  child: ItineraryCanvas(
                    tripId: widget.tripId,
                    activeDay: _activeDay,
                    onDayChanged: _onDayChanged,
                  ),
                ),
                const VerticalDivider(width: 1, color: AppTheme.divider),
                SizedBox(
                  width: right,
                  child: SummarySidebar(
                      tripId: widget.tripId, activeDay: _activeDay),
                ),
              ],
            );
          }
          // < 900: single column. Canvas (primary) → Discovery, with Summary
          // pinned as a peeking bottom sheet. Its expand/collapse lands in File 12.
          return Stack(
            children: [
              Positioned.fill(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 140),
                  children: [
                    ItineraryCanvas(
                      tripId: widget.tripId,
                      activeDay: _activeDay,
                      onDayChanged: _onDayChanged,
                    ),
                    DiscoveryPanel(tripId: widget.tripId),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SummarySidebar(
                  tripId: widget.tripId,
                  activeDay: _activeDay,
                  collapsed: true, // peek mode at mobile widths
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- State 1: loading (trip not yet cached) ----
  // Skeleton mirrors the mobile shape (canvas → discovery → summary peek) so the
  // layout doesn't jump on first paint — a shape promise, not just "loading".
  Widget _skeleton() {
    Widget block() => Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
        );
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        // TODO(tab-deeplink): target the Trips tab once it's deep-linkable.
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? Row(children: [
                SizedBox(width: 260, child: block()),
                Expanded(child: block()),
                SizedBox(width: 300, child: block()),
              ])
            : Column(children: [
                Expanded(flex: 3, child: block()), // canvas placeholder
                Expanded(flex: 2, child: block()), // discovery placeholder
                SizedBox(height: 120, child: block()), // summary peek placeholder
              ]),
      ),
    );
  }

  // ---- State 3: error ----
  Widget _errorState(BuildContext context, String message) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        // TODO(tab-deeplink): target the Trips tab once it's deep-linkable.
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
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
                  style:
                      TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
              const SizedBox(height: 6),
              // Raw error kept as a clipped diagnostic breadcrumb for support.
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

  // ---- State 2: not found (after load) ----
  Widget _notFound(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        // TODO(tab-deeplink): target the Trips tab once it's deep-linkable.
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
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
}

/// Rich app bar for the loaded builder: trip name + date-range chip + a live
/// spent/budget pill + Share. Subscribes narrowly — the trip slice drives the
/// name/dates, a separate [totalSpent] slice drives only the pill, so stop
/// mutations repaint the pill without rebuilding the whole header.
class _TripBuilderHeader extends StatelessWidget implements PreferredSizeWidget {
  const _TripBuilderHeader({required this.tripId, required this.isMobile});

  final String tripId;
  final bool isMobile;

  @override
  Size get preferredSize => Size.fromHeight(isMobile ? 56 : 64);

  @override
  Widget build(BuildContext context) {
    final trip = context.select<TripProvider, Trip?>((p) => p.tripById(tripId));
    // Header only renders inside the loaded branch, but stay defensive: if the
    // trip vanished mid-frame, fall back to a bare bar rather than throwing.
    if (trip == null) {
      return AppBar(
        backgroundColor: AppTheme.surface,
        leading: BackButton(onPressed: () => context.go('/profile')),
      );
    }
    final spent = context.select<TripProvider, int>((p) => p.totalSpent(tripId));

    return AppBar(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: preferredSize.height,
      titleSpacing: 0,
      // TODO(tab-deeplink): target the Trips tab once it's deep-linkable.
      leading: BackButton(onPressed: () => context.go('/profile')),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            trip.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          // On mobile the date lives under the name (no room in the actions row).
          if (isMobile)
            Text(
              '${Trip.formatDateRange(trip.startDate, trip.endDate)} · ${trip.nights} ${trip.nights == 1 ? 'night' : 'nights'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11),
            ),
        ],
      ),
      actions: [
        if (!isMobile) ...[
          _DateChip(
              start: trip.startDate, end: trip.endDate, nights: trip.nights),
          const SizedBox(width: 10),
        ],
        _BudgetPill(budgetVnd: trip.budgetVnd, spent: spent),
        IconButton(
          icon: const Icon(Icons.share_outlined, color: AppTheme.textSecondary),
          tooltip: 'Share',
          // TODO(share): open the collaborator/share sheet once it lands.
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share coming soon')),
          ),
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppTheme.divider),
      ),
    );
  }
}

/// Muted date-range chip: 'Jul 12 – 18 · 6 nights'. Desktop only (mobile folds
/// the range under the title). Formatting is [Trip.formatDateRange]'s job.
class _DateChip extends StatelessWidget {
  const _DateChip(
      {required this.start, required this.end, required this.nights});

  final DateTime start;
  final DateTime end;
  final int nights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today,
              size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            '${Trip.formatDateRange(start, end)} · $nights ${nights == 1 ? 'night' : 'nights'}',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Live spend indicator with three states keyed off spent ÷ budget:
///   > 100%   → danger border, 'over' framing ('₫X · ₫Z over')
///   90–100%  → warn border (approaching the cap)
///   < 90%    → primary border, '₫X of ₫Y' with the cap muted
/// Two-tone via [Text.rich] so the spent figure reads first. Short-form money.
class _BudgetPill extends StatelessWidget {
  const _BudgetPill({required this.budgetVnd, required this.spent});

  final int budgetVnd;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: budgetVnd);
    final over = status.over;
    final accent = status.accent;

    final spentSpan = TextSpan(
      text: '₫${Trip.formatVnd(spent, short: true)}',
      style: TextStyle(color: accent, fontWeight: FontWeight.w700),
    );
    final tail = over
        ? TextSpan(
            text: ' · ₫${Trip.formatVnd(spent - budgetVnd, short: true)} over',
            style: const TextStyle(
                color: AppTheme.danger, fontWeight: FontWeight.w600))
        : TextSpan(
            text: ' of ₫${Trip.formatVnd(budgetVnd, short: true)}',
            style: const TextStyle(color: AppTheme.textSecondary));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent),
      ),
      child: Text.rich(
        TextSpan(children: [spentSpan, tail]),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

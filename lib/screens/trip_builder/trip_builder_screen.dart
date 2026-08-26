import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/logic/currency.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/budget_status.dart';
import '../profile/profile_screen.dart';
import 'widgets/itinerary_canvas.dart';
import 'widgets/summary_sidebar.dart';

/// The trip is auto-saved throughout the builder (createTrip commits before
/// this screen ever mounts; every stop add persists immediately), so "back"
/// never needs to save/discard — it just navigates. Lands on My Trip's
/// Itinerary segment for this specific trip via ProfileDeepLink, closing the
/// tab-deeplink gap every call site here used to carry as a TODO.
void _exitToItinerary(BuildContext context, {String? tripId}) {
  context.go('/profile',
      extra: ProfileDeepLink(
          tab: 1, tripId: tripId, segment: TripDetailSegment.itinerary));
}

/// Matches [SummarySidebar]'s `_MobilePeek` fixed height.
const double _kSummaryPeekHeight = 120;

/// Floating bottom-right confirm-and-exit affordance. Every stop already
/// writes to Supabase the moment it's added (see _exitToItinerary's doc
/// comment above) — there is no batched/deferred itinerary state left to
/// persist here, so this button has nothing to actually save. It exists as a
/// deliberate "I'm done" moment for the user, and reuses the exact same
/// _exitToItinerary navigation the header close icon and system back gesture
/// already use, so every exit path — tap here, tap close, swipe back — lands
/// in the same place.
class _SaveTripButton extends StatelessWidget {
  const _SaveTripButton({required this.tripId});
  final String tripId;

  void _onTap(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip saved')),
    );
    _exitToItinerary(context, tripId: tripId);
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _onTap(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        shadowColor: AppTheme.primary.withValues(alpha: 0.4),
      ),
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Save trip',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }
}

/// Boxed icon affordance — pixel-identical to the "+ New Trip" wizard's close
/// button (trip_setup_sheet.dart's header), reused here so the builder's exit
/// control and share icon read as the same visual language as the rest of the
/// trip-creation flow, not a stock unstyled BackButton/IconButton.
class _HeaderIconBox extends StatelessWidget {
  const _HeaderIconBox(
      {required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Icon(icon, color: AppTheme.lightMute, size: 20),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

/// Full-screen 2-pane Trip Builder (Itinerary + Summary). Subscriber, not
/// owner: the only local state is [_activeDay]; trips/stops live on
/// TripProvider. Discovery is no longer a standalone pane/sheet here — gems
/// are found and attached through [AddStopSheet], opened from each slot's
/// "+ Add" (see itinerary_canvas.dart's `TimeSlotBlock`).
class TripBuilderScreen extends StatefulWidget {
  const TripBuilderScreen({super.key, required this.tripId, this.initialDay});
  final String tripId;

  /// Day to land on, e.g. when arriving from My Trip's "+ Add activity" for a
  /// specific day. Defaults to Day 1 when absent.
  final int? initialDay;

  @override
  State<TripBuilderScreen> createState() => _TripBuilderScreenState();
}

class _TripBuilderScreenState extends State<TripBuilderScreen> {
  late int _activeDay = widget.initialDay ?? 1;
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
    final child = trip != null
        ? _loaded(context, trip)
        : isLoading
            ? _skeleton()
            : error != null
                ? _errorState(context, error)
                : _notFound(context);

    // This screen is reached via router.push (trip_setup_sheet.dart), so it
    // sits on top of the just-completed "+ New Trip" wizard sheet in the
    // Navigator stack. An unhandled system back gesture/hardware button would
    // pop straight into that now-stale sheet instead of landing on the trip —
    // intercept it and route through the same itinerary deep link the header
    // back button uses, so every exit path is consistent.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitToItinerary(context, tripId: widget.tripId);
      },
      child: child,
    );
  }

  // ---- State 4: loaded → responsive 3-pane ----
  Widget _loaded(BuildContext context, Trip trip) {
    // Computed once so the header's height/layout and the body breakpoints agree
    // on a single source of truth (width is identical either side of the app bar,
    // so there's no mismatch to reconcile).
    final isMobile = MediaQuery.of(context).size.width < Breakpoints.desktop;
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: _TripBuilderHeader(tripId: widget.tripId, isMobile: isMobile),
      // Stack, not just the LayoutBuilder directly: _SaveTripButton floats in
      // the bottom-right corner over whichever layout is active below, rather
      // than being squeezed into SummarySidebar's already-tappable, height-
      // constrained mobile peek bar (see _kSummaryPeekHeight) or reworked into
      // the desktop sidebar's own Row/Column — one placement, both breakpoints.
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w >= Breakpoints.desktop) {
                final right = w >= 1100 ? 320.0 : 280.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ItineraryCanvas(
                        tripId: widget.tripId,
                        activeDay: _activeDay,
                        onDayChanged: _onDayChanged,
                      ),
                    ),
                    const VerticalDivider(width: 1, color: AppTheme.lightBorder),
                    SizedBox(
                      width: right,
                      child: SummarySidebar(
                          tripId: widget.tripId, activeDay: _activeDay),
                    ),
                  ],
                );
              }
              // < 900: itinerary fills the space above the Summary peek. No more
              // floating Discovery layer to reserve room for — AddStopSheet is a
              // modal (showModalBottomSheet from each slot's "+ Add"), not a
              // persistent overlay, so a plain Column replaces the old
              // Stack/Positioned composition entirely.
              return Column(
                children: [
                  Expanded(
                    child: ItineraryCanvas(
                      tripId: widget.tripId,
                      activeDay: _activeDay,
                      onDayChanged: _onDayChanged,
                    ),
                  ),
                  SummarySidebar(
                    tripId: widget.tripId,
                    activeDay: _activeDay,
                    collapsed: true, // peek mode at mobile widths
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            // Clears SummarySidebar's mobile peek bar (fixed _kSummaryPeekHeight)
            // plus a 16px gap; on desktop the sidebar is a scrollable panel with
            // no fixed bottom bar to clear, so just the screen-edge margin.
            bottom: (isMobile ? _kSummaryPeekHeight : 0) + 16,
            child: _SaveTripButton(tripId: widget.tripId),
          ),
        ],
      ),
    );
  }

  // ---- State 1: loading (trip not yet cached) ----
  // Skeleton mirrors the 2-pane shape (canvas + summary) so the layout
  // doesn't jump on first paint — a shape promise, not just "loading".
  Widget _skeleton() {
    Widget block() => Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(12),
          ),
        );
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        leading: Center(
          child: _HeaderIconBox(
            icon: Icons.close,
            onTap: () => _exitToItinerary(context, tripId: widget.tripId),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= Breakpoints.desktop
            ? Row(children: [
                Expanded(child: block()),
                SizedBox(width: 300, child: block()),
              ])
            : Column(children: [
                Expanded(child: block()), // canvas placeholder
                SizedBox(
                    height: _kSummaryPeekHeight,
                    child: block()), // summary peek placeholder
              ]),
      ),
    );
  }

  // ---- State 3: error ----
  Widget _errorState(BuildContext context, String message) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        leading: Center(
          child: _HeaderIconBox(
            icon: Icons.close,
            onTap: () => _exitToItinerary(context, tripId: widget.tripId),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppTheme.lightMute, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load this trip.",
                  style:
                      TextStyle(color: AppTheme.lightInk, fontSize: 16)),
              const SizedBox(height: 6),
              // Raw error kept as a clipped diagnostic breadcrumb for support.
              Text(message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.lightMute, fontSize: 12)),
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
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        leading: Center(
          child: _HeaderIconBox(
            icon: Icons.close,
            onTap: () => _exitToItinerary(context),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined,
                  color: AppTheme.lightMute, size: 40),
              const SizedBox(height: 12),
              const Text("This trip doesn't exist or isn't yours.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.lightMute)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _exitToItinerary(context),
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
        backgroundColor: AppTheme.lightSurface,
        leading: Center(
          child: _HeaderIconBox(
            icon: Icons.close,
            onTap: () => _exitToItinerary(context, tripId: tripId),
          ),
        ),
      );
    }
    final spent = context.select<TripProvider, int>((p) => p.totalSpent(tripId));

    return AppBar(
      backgroundColor: AppTheme.lightSurface,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: preferredSize.height,
      titleSpacing: 0,
      leading: Center(
        child: _HeaderIconBox(
          icon: Icons.close,
          onTap: () => _exitToItinerary(context, tripId: tripId),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            trip.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.lightInk,
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
                  color: AppTheme.lightMute, fontSize: 11),
            ),
        ],
      ),
      actions: [
        if (!isMobile) ...[
          _DateChip(
              start: trip.startDate, end: trip.endDate, nights: trip.nights),
          const SizedBox(width: 10),
        ],
        _BudgetPill(
            budgetVnd: trip.budgetVnd,
            spent: spent,
            symbol: currencyFor(trip.currency).symbol),
        const SizedBox(width: 8),
        _HeaderIconBox(
          icon: Icons.share_outlined,
          tooltip: 'Share',
          // TODO(share): open the collaborator/share sheet once it lands.
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share coming soon')),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppTheme.lightBorder),
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
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today,
              size: 14, color: AppTheme.lightMute),
          const SizedBox(width: 6),
          Text(
            '${Trip.formatDateRange(start, end)} · $nights ${nights == 1 ? 'night' : 'nights'}',
            style: const TextStyle(
                color: AppTheme.lightMute,
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
  const _BudgetPill(
      {required this.budgetVnd, required this.spent, required this.symbol});

  final int budgetVnd;
  final int spent;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: budgetVnd);
    final over = status.over;
    final accent = status.accent;

    final spentSpan = TextSpan(
      text: '$symbol${Trip.formatVnd(spent, short: true)}',
      style: TextStyle(color: accent, fontWeight: FontWeight.w700),
    );
    final tail = over
        ? TextSpan(
            text: ' · $symbol${Trip.formatVnd(spent - budgetVnd, short: true)} over',
            style: const TextStyle(
                color: AppTheme.danger, fontWeight: FontWeight.w600))
        : TextSpan(
            text: ' of $symbol${Trip.formatVnd(budgetVnd, short: true)}',
            style: const TextStyle(color: AppTheme.lightMute));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
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

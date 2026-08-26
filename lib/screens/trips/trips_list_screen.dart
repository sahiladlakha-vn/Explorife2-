import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/budget_status.dart';

/// Full trip list — every trip the user owns, bucketed Active-Soon /
/// Upcoming / Past. Reached from the side drawer's "My Trips" tile AND from
/// My Trip tab's list-icon button. Moved out of the profile "My Trip" tab
/// (see ADR in trips_tab.dart) once that tab narrowed to a single
/// active-trip view — this screen is the place to browse or create trips
/// beyond the active one.
///
/// [_tripListSections]/[_TripRow] below are also reused, unmodified, by
/// [showTripSwitcherSheet] — the two surfaces render identical rows and
/// only differ in outer chrome (full Scaffold+AppBar+FAB vs. a lightweight
/// bottom sheet) and what tapping a row does (navigate away here; swap the
/// active trip in place there — see that function's doc comment for why
/// picking a trip can't mean the same thing in both places).
class TripsListScreen extends StatelessWidget {
  const TripsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final all = provider.trips; // provider sorts soonest startDate first

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.lightSurface,
            title: Text('MY TRIPS',
                style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
          ),
          if (all.isEmpty)
            SliverToBoxAdapter(
              child: _emptyState(
                context,
                icon: Icons.map_outlined,
                title: 'No trips yet',
                subtitle: "Plan your first and it'll show up here.",
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_tripListSections(
                  all,
                  provider,
                  onTapTrip: (id) => context.go('/trips/$id'),
                )),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trips/new'),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('New Trip',
            style: GoogleFonts.fredoka(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Opens the exact same trip list [TripsListScreen] renders — same rows,
/// same ACTIVE·SOON/UPCOMING/PAST sections, same progress-% pills — as a
/// quick-switch bottom sheet instead of a full page. For the chevron next
/// to My Trip's title (trips_tab.dart), which needs to swap which trip that
/// tab is showing WITHOUT leaving it — unlike the list-icon button a few
/// widgets over, which deliberately navigates to the full /trips page.
/// Picking a trip here calls [onSelect] and closes the sheet rather than
/// navigating to TripSummaryScreen — a full-page navigation would defeat
/// the point of a quick in-place switch, and TripSummaryScreen is a
/// different screen from My Trip's tab entirely, not where "switching
/// trips" should land you when you started inside that tab. Replaces the
/// old, separate _TripSwitcherSheet (bare name+dates list) with this same
/// richer content instead of duplicating a second, simpler list widget.
Future<void> showTripSwitcherSheet(
  BuildContext context, {
  required String currentTripId,
  required ValueChanged<String> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TripSwitcherSheetBody(currentTripId: currentTripId, onSelect: onSelect),
  );
}

class _TripSwitcherSheetBody extends StatelessWidget {
  const _TripSwitcherSheetBody({required this.currentTripId, required this.onSelect});

  final String currentTripId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final all = provider.trips;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.lightSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.lightBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('MY TRIPS',
                    style: GoogleFonts.bebasNeue(
                        fontSize: 20, color: AppTheme.lightInk, letterSpacing: 0.5)),
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? _emptyState(
                      context,
                      icon: Icons.map_outlined,
                      title: 'No trips yet',
                      subtitle: "Plan your first and it'll show up here.",
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: _tripListSections(
                        all,
                        provider,
                        currentTripId: currentTripId,
                        onTapTrip: (id) {
                          onSelect(id);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _tripListSections(
  List<Trip> all,
  TripProvider provider, {
  String? currentTripId,
  required ValueChanged<String> onTapTrip,
}) {
  final soon = <Trip>[], upcoming = <Trip>[], past = <Trip>[];
  for (final t in all) {
    if (t.daysUntilStart < 0) {
      past.add(t);
    } else if (t.isUpcoming) {
      soon.add(t);
    } else {
      upcoming.add(t);
    }
  }
  past.sort((a, b) => b.startDate.compareTo(a.startDate));

  return [
    ..._tripSection('ACTIVE · SOON', soon, provider, currentTripId, onTapTrip),
    ..._tripSection('UPCOMING', upcoming, provider, currentTripId, onTapTrip),
    ..._tripSection('PAST', past, provider, currentTripId, onTapTrip),
  ];
}

List<Widget> _tripSection(String label, List<Trip> trips, TripProvider p,
    String? currentTripId, ValueChanged<String> onTapTrip) {
  if (trips.isEmpty) return const [];
  return [
    _SectionHeader(label: label),
    const SizedBox(height: 8),
    _TripGroupCard(
      children: [
        for (final (i, t) in trips.indexed)
          _TripRow(
            trip: t,
            divider: i > 0,
            spent: p.totalSpent(t.id),
            current: t.id == currentTripId,
            onTap: () => onTapTrip(t.id),
          ),
      ],
    ),
    const SizedBox(height: 16),
  ];
}

Widget _emptyState(BuildContext context,
    {required IconData icon, required String title, required String subtitle}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppTheme.lightMute),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.bebasNeue(
                  fontSize: 22, color: AppTheme.lightMute, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.fredoka(
                  fontSize: 14, color: AppTheme.lightMute, height: 1.5)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.push('/trips/new'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text('Create a trip',
                style: GoogleFonts.fredoka(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.map_outlined, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _TripGroupCard extends StatelessWidget {
  final List<Widget> children;
  const _TripGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _TripRow extends StatelessWidget {
  final Trip trip;
  final bool divider;
  final int spent;
  final VoidCallback onTap;
  // True when this is the trip the switcher sheet was opened FOR — unused
  // (always false) on the full /trips page, which has no single "current"
  // trip concept the way a quick-switch sheet does. Preserves the old
  // _TripSwitcherSheet's current-trip checkmark rather than losing it in
  // the move to these richer rows.
  final bool current;
  const _TripRow(
      {required this.trip,
      required this.divider,
      required this.spent,
      required this.onTap,
      this.current = false});

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: trip.budgetVnd);
    final pct = status.pct.round();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: current ? AppTheme.primary.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(10),
          border: divider
              ? const Border(top: BorderSide(color: AppTheme.lightBorder))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.map_outlined,
                  size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.lightInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Trip.formatDateRange(trip.startDate, trip.endDate)
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: AppTheme.lightMute,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: status.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: status.accent.withValues(alpha: 0.5)),
              ),
              child: Text('$pct%',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: status.accent,
                      letterSpacing: 0.3)),
            ),
            if (current) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, size: 18, color: AppTheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

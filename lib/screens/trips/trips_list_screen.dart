import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/budget_status.dart';

/// Full trip list — every trip the user owns, bucketed Active-Soon /
/// Upcoming / Past. Reached from the side drawer's "My Trips" tile. Moved out
/// of the profile "My Trip" tab (see ADR in trips_tab.dart) once that tab
/// narrowed to a single active-trip view — this screen is the sole place left
/// to browse or create trips beyond the active one.
class TripsListScreen extends StatelessWidget {
  const TripsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final all = provider.trips; // provider sorts soonest startDate first

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bg,
            title: Text('MY TRIPS',
                style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
          ),
          if (all.isEmpty)
            SliverToBoxAdapter(
              child: _empty(
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
                delegate: SliverChildListDelegate(_sections(all, provider)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trips/new'),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('New Trip',
            style: GoogleFonts.dmSans(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  List<Widget> _sections(List<Trip> all, TripProvider provider) {
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
      ..._section('ACTIVE · SOON', soon, provider),
      ..._section('UPCOMING', upcoming, provider),
      ..._section('PAST', past, provider),
    ];
  }

  List<Widget> _section(String label, List<Trip> trips, TripProvider p) {
    if (trips.isEmpty) return const [];
    return [
      _SectionHeader(label: label),
      const SizedBox(height: 8),
      _TripGroupCard(
        children: [
          for (final (i, t) in trips.indexed)
            _TripRow(trip: t, divider: i > 0, spent: p.totalSpent(t.id)),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _empty(BuildContext context,
      {required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.bebasNeue(
                    fontSize: 22, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppTheme.textSecondary, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.push('/trips/new'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text('Create a trip',
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: children),
    );
  }
}

class _TripRow extends StatelessWidget {
  final Trip trip;
  final bool divider;
  final int spent;
  const _TripRow(
      {required this.trip, required this.divider, required this.spent});

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: trip.budgetVnd);
    final pct = status.pct.round();
    return GestureDetector(
      onTap: () => context.go('/trips/${trip.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: AppTheme.divider))
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
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Trip.formatDateRange(trip.startDate, trip.endDate)
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
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
          ],
        ),
      ),
    );
  }
}

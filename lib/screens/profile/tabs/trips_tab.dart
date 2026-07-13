part of '../profile_screen.dart';

// My Trips tab: trip list, trip row, create-trip button.

// ─────────────────────────────────────────
// MY TRIPS TAB
// ─────────────────────────────────────────
/// Full trip list, bucketed by proximity. Uses the same daysUntilStart split
/// as [TripProvider.activeTrip]: 0–30 days is "soon", beyond that "upcoming",
/// negative is "past". Rows rhyme with [_GemRow]; sections use [_CardHeader].
class _TripsTab extends StatelessWidget {
  const _TripsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final all = provider.trips; // provider sorts soonest startDate first

    if (all.isEmpty) {
      return _EmptyState(
        icon: Icons.map_outlined,
        title: 'No trips yet',
        subtitle: 'Plan your first and it\'ll show up here.',
        cta: 'Create a trip',
        onTap: () => context.go('/trips/new'),
      );
    }

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
    // soon/upcoming inherit soonest-first order; past reads most-recent first.
    past.sort((a, b) => b.startDate.compareTo(a.startDate));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _CreateTripButton(onTap: () => context.go('/trips/new')),
        const SizedBox(height: 16),
        ..._section('ACTIVE · SOON', soon, provider),
        ..._section('UPCOMING', upcoming, provider),
        ..._section('PAST', past, provider),
      ],
    );
  }

  // Section = _CardHeader + a _Card of _TripRow siblings. Empty groups skipped,
  // so the gaps land only where there's content.
  List<Widget> _section(String label, List<Trip> trips, TripProvider p) {
    if (trips.isEmpty) return const [];
    return [
      _CardHeader(
          icon: Icons.map_outlined, label: label, color: AppTheme.primary),
      const SizedBox(height: 8),
      _Card(
        child: Column(
          children: [
            for (final (i, t) in trips.indexed)
              _TripRow(trip: t, divider: i > 0, spent: p.totalSpent(t.id)),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}

/// One trip in the MY TRIPS list — the [_GemRow] idiom (tinted leading tile,
/// name + subtitle, trailing accent) with a budget-pct pill instead of a
/// chevron. Taps into the trip summary.
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
              ? const Border(top: BorderSide(color: _kBorder))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
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
                        color: _kInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Trip.formatDateRange(trip.startDate, trip.endDate)
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: _kMute, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Budget-pct pill. Only meaningful once a budget is set; unset
            // budgets read as 0% so the pill stays honest rather than blank.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: status.accent.withValues(alpha: 0.10),
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

/// Full-width primary CTA atop the MY TRIPS list.
class _CreateTripButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateTripButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text('Create new trip',
                style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}


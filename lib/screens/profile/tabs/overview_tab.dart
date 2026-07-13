part of '../profile_screen.dart';

// Overview tab + next-trip card and its sub-widgets.

// ─────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final double spent;
  final int groups;    // split groups → "Groups settled"
  final int tripCount; // real trips → avg-per-trip divisor
  final List<Story> stories;
  final List<Gem> gems;
  // Derived-insight inputs, computed once in the shell (shared `now`). [alerts]
  // is the full severity-desc list (this tab caps display at 4); [pace] and
  // [budgetVnd] are null together when there's no active trip → both insight
  // cards are simply absent and the existing empty flow is untouched.
  final List<Alert> alerts;
  final TripPace? pace;
  final int? budgetVnd;
  const _OverviewTab({
    required this.spent,
    required this.groups,
    required this.tripCount,
    required this.stories,
    required this.gems,
    required this.alerts,
    required this.pace,
    required this.budgetVnd,
  });

  @override
  Widget build(BuildContext context) {
    final avg = tripCount > 0 ? spent / tripCount : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        // Next / upcoming trip pulse — first thing a returning user sees.
        const _NextTripCard(),
        const SizedBox(height: 16),

        // Derived alerts — most actionable, so directly under the trip pulse.
        // Absent when the active trip has nothing flagged.
        if (alerts.isNotEmpty) ...[
          _AlertsCard(alerts: alerts),
          const SizedBox(height: 16),
        ],

        // Budget pace — present for any active trip (honest not-started/no-budget
        // states included); absent only when there's no active trip.
        if (pace != null) ...[
          _PaceCard(pace: pace!, budgetVnd: budgetVnd ?? 0),
          const SizedBox(height: 16),
        ],

        // Expense summary
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.trending_up, label: 'EXPENSE SUMMARY', color: _kTeal),
              const SizedBox(height: 16),
              _summaryRow('Total across all trips',
                  '\$${spent.toStringAsFixed(1)}', _kInk),
              const SizedBox(height: 14),
              _summaryRow('Average per trip',
                  '\$${avg.toStringAsFixed(2)}', _kInk),
              const SizedBox(height: 14),
              _summaryRow('Groups settled', '$groups / $groups', _kTeal),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  value: 1,
                  minHeight: 5,
                  backgroundColor: _kBorder,
                  valueColor: AlwaysStoppedAnimation(_kTeal),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Recent stories
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.menu_book_outlined,
                  label: 'RECENT STORIES',
                  color: AppTheme.primary),
              const SizedBox(height: 8),
              if (stories.isEmpty)
                _emptyLine('You haven\'t submitted any stories yet.')
              else
                ...stories.take(3).toList().asMap().entries.map((e) =>
                    _StoryRow(story: e.value, divider: e.key > 0)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Saved / my gems
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.diamond_outlined,
                  label: 'MY GEMS',
                  color: AppTheme.primary),
              const SizedBox(height: 8),
              if (gems.isEmpty)
                _emptyLine('Drop your first gem from the map.')
              else
                ...gems.take(3).toList().asMap().entries.map((e) =>
                    _GemRow(gem: e.value, divider: e.key > 0)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF555555))),
        ),
        Text(value,
            style: GoogleFonts.dmSans(
                fontSize: 17, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text,
            style: GoogleFonts.dmSans(fontSize: 13, color: _kMute)),
      );
}

// ─────────────────────────────────────────
// NEXT TRIP CARD (Overview)
// ─────────────────────────────────────────
/// Overview's trip pulse. Three states, one widget — the two *empty* states
/// carry different copy on purpose: a user with past trips must not be told to
/// "plan your first". Compact by design (Overview stacks cards below it); the
/// full-width create CTA lives on the MY TRIPS tab, not here.
class _NextTripCard extends StatelessWidget {
  const _NextTripCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final active = provider.activeTrip; // soonest trip within 30 days, or null
    final hasHistory = provider.trips.isNotEmpty;

    // State A — no upcoming trip AND no trips ever: first-run nudge + chip CTA.
    if (active == null && !hasHistory) {
      return _NextTripShell(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No trips yet',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kInk)),
                  const SizedBox(height: 2),
                  Text('Plan your first adventure.',
                      style:
                          GoogleFonts.dmSans(fontSize: 13, color: _kMute)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _TripChipCta(
                label: '+ New trip', onTap: () => context.go('/trips/new')),
          ],
        ),
      );
    }

    // State B — trips exist but none upcoming: past-trips nudge. Whole card is
    // tappable; a right-side chevron (matching State C) carries the affordance
    // so B and C read as one widget in two data modes.
    if (active == null) {
      return GestureDetector(
        onTap: () => context.go('/trips/new'),
        behavior: HitTestBehavior.opaque,
        child: _NextTripShell(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No trips coming up',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _kInk)),
                    const SizedBox(height: 2),
                    Text('Plan your next trip',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: _kMute),
            ],
          ),
        ),
      );
    }

    // State C — populated: identity + mini budget bar (fraction only; the
    // category breakdown lives in the builder, not here).
    final spent = provider.totalSpent(active.id);
    final status = BudgetStatus.of(spent: spent, budgetVnd: active.budgetVnd);
    final fill = (status.pct / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => context.go('/trips/${active.id}'),
      behavior: HitTestBehavior.opaque,
      child: _NextTripShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.luggage,
                      size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(active.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _kInk)),
                      const SizedBox(height: 2),
                      Text(
                        Trip.formatDateRange(active.startDate, active.endDate),
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 11, color: _kMute, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: _kMute),
              ],
            ),
            const SizedBox(height: 12),
            // Mini budget bar — same accent state machine as the sidebar.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: _kBorder),
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(height: 6, color: status.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '₫${Trip.formatVnd(spent, short: true)} of '
              '₫${Trip.formatVnd(active.budgetVnd, short: true)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: _kMute, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card chrome shared by all three [_NextTripCard] states — same fill /
/// border / radius as [_Card] but tuned padding for the denser trip content.
class _NextTripShell extends StatelessWidget {
  final Widget child;
  const _NextTripShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

/// Small pill CTA used by [_NextTripCard]'s first-run state.
class _TripChipCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TripChipCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

// ─────────────────────────────────────────
// ALERTS CARD (Overview)
// ─────────────────────────────────────────
/// Renders the top [_kAlertCap] alerts (the list arrives severity-desc from
/// tripAlerts, so the head is the most urgent) with a muted "+N more" line for
/// the remainder. Static in v1 — the stopId/bookingId/category each Alert
/// carries are future-proofing for deep-links, wired in a later step.
class _AlertsCard extends StatelessWidget {
  final List<Alert> alerts;
  const _AlertsCard({required this.alerts});

  static const int _kAlertCap = 4;

  @override
  Widget build(BuildContext context) {
    final shown = alerts.take(_kAlertCap).toList();
    final extra = alerts.length - shown.length;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
              icon: Icons.notifications_none, label: 'ALERTS', color: _kInk),
          const SizedBox(height: 4),
          ...shown.asMap().entries.map(
              (e) => _AlertRow(alert: e.value, divider: e.key > 0)),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('+$extra more',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: _kMute, letterSpacing: 0.5)),
            ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final Alert alert;
  final bool divider;
  const _AlertRow({required this.alert, required this.divider});

  @override
  Widget build(BuildContext context) {
    final accent = _alertAccent(alert.severity);
    final copy = _alertCopy(alert);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border:
            divider ? const Border(top: BorderSide(color: _kBorder)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_alertIcon(alert.kind), size: 17, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy.title,
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kInk)),
                const SizedBox(height: 2),
                Text(copy.body,
                    style: GoogleFonts.dmSans(
                        fontSize: 12.5, color: _kMute, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Severity → accent. Audit-first: maps onto the named palette tokens
/// (_kCritical/_kWarn added for this, _kTeal existing), not ad-hoc colours.
Color _alertAccent(AlertSeverity s) => switch (s) {
      AlertSeverity.critical => _kCritical,
      AlertSeverity.warning => _kWarn,
      AlertSeverity.info => _kTeal,
    };

IconData _alertIcon(AlertKind k) => switch (k) {
      AlertKind.unbookedStop => Icons.link_off,
      AlertKind.overBudgetCategory => Icons.warning_amber_rounded,
      AlertKind.upcomingBooking => Icons.schedule,
    };

/// The copy layer. Lives HERE (UI), never in trip_insights — the pure layer
/// stays string-free and emits structured payloads this formatter interpolates.
({String title, String body}) _alertCopy(Alert a) {
  switch (a.kind) {
    case AlertKind.unbookedStop:
      final price = a.payload['priceVnd'] ?? 0;
      return (
        title: 'Nothing booked yet',
        body: price > 0
            ? '₫${Trip.formatVnd(price, short: true)} planned — no booking against it.'
            : 'A planned stop has no booking yet.',
      );
    case AlertKind.overBudgetCategory:
      final over = a.payload['overVnd'] ?? 0;
      final actual = a.payload['actualVnd'] ?? 0;
      final planned = a.payload['plannedVnd'] ?? 0;
      final cat = _capitalize(a.category);
      return (
        title: '$cat over budget',
        body: '₫${Trip.formatVnd(actual, short: true)} of '
            '₫${Trip.formatVnd(planned, short: true)} · '
            '₫${Trip.formatVnd(over, short: true)} over.',
      );
    case AlertKind.upcomingBooking:
      // Severity encodes to_book (critical) vs booked/paid (info) at the
      // producer, so the copy reads it rather than re-deriving status.
      final d = a.payload['daysUntil'] ?? 0;
      final soon = d <= 0 ? 'today' : (d == 1 ? 'in 1 day' : 'in $d days');
      return a.severity == AlertSeverity.critical
          ? (
              title: 'Book this soon',
              body: 'Starts $soon and isn\'t reserved yet.'
            )
          : (title: 'Upcoming booking', body: 'Starts $soon.');
  }
}

String _capitalize(String? s) {
  if (s == null || s.isEmpty) return 'Category';
  return s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────
// BUDGET PACE CARD (Overview)
// ─────────────────────────────────────────
/// Straight-line burn vs budget. The two null-bar states (notStarted, noBudget)
/// render as honest text — never a collapsed zero-width bar. The active states
/// draw an actual-fill bar with an expected-position tick, accent-coloured by
/// pace status.
class _PaceCard extends StatelessWidget {
  final TripPace pace;
  final int budgetVnd;
  const _PaceCard({required this.pace, required this.budgetVnd});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
              icon: Icons.speed, label: 'BUDGET PACE', color: _kTeal),
          const SizedBox(height: 14),
          ..._content(),
        ],
      ),
    );
  }

  List<Widget> _content() {
    switch (pace.status) {
      case PaceStatus.notStarted:
        return [
          _headline("Trip hasn't started", _kInk),
          const SizedBox(height: 4),
          _mono(
              'Day 0 of ${pace.tripDays} · ₫${Trip.formatVnd(budgetVnd, short: true)} planned'),
        ];
      case PaceStatus.noBudget:
        return [
          _headline('No budget set', _kInk),
          const SizedBox(height: 4),
          _mono(
              '₫${Trip.formatVnd(pace.cumulativeActual, short: true)} committed so far'),
        ];
      case PaceStatus.underPace:
      case PaceStatus.onPace:
      case PaceStatus.overPace:
        return _activeContent();
    }
  }

  List<Widget> _activeContent() {
    final accent = switch (pace.status) {
      PaceStatus.overPace => _kCritical,
      PaceStatus.onPace => _kGreen,
      PaceStatus.underPace => _kTeal,
      _ => _kMute,
    };
    final deltaText = switch (pace.status) {
      PaceStatus.overPace =>
        '₫${Trip.formatVnd(pace.delta, short: true)} over pace',
      PaceStatus.underPace =>
        '₫${Trip.formatVnd(pace.delta.abs(), short: true)} under pace',
      _ => 'On pace',
    };
    final actualFill =
        budgetVnd > 0 ? (pace.cumulativeActual / budgetVnd).clamp(0.0, 1.0) : 0.0;
    final expectedFill =
        budgetVnd > 0 ? (pace.expectedByToday / budgetVnd).clamp(0.0, 1.0) : 0.0;
    return [
      Row(
        children: [
          Expanded(
              child: _mono('Day ${pace.tripDayToday} of ${pace.tripDays}')),
          Text(deltaText,
              style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
        ],
      ),
      const SizedBox(height: 10),
      // Actual-fill bar + expected-position tick. Same Stack idiom as the
      // _NextTripCard mini-bar; the tick is Aligned by fraction (−1..1).
      SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(color: _kBorder),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: actualFill,
                    child: Container(color: accent),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment(expectedFill * 2 - 1, 0),
                child: Container(width: 2, color: _kInk),
              ),
            ),
          ],
        ),
      ),
      if (pace.projectedExhaustionDay != null) ...[
        const SizedBox(height: 8),
        _mono('Budget runs out ~day ${pace.projectedExhaustionDay}'),
      ],
    ];
  }

  Widget _headline(String t, Color c) => Text(t,
      style: GoogleFonts.dmSans(
          fontSize: 15, fontWeight: FontWeight.w800, color: c));

  Widget _mono(String t) => Text(t,
      style: GoogleFonts.jetBrainsMono(
          fontSize: 11, color: _kMute, letterSpacing: 0.3));
}


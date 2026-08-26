part of '../profile_screen.dart';

// Overview tab + next-trip card and its sub-widgets.

// ─────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final double spent;
  final int groups; // split groups → "Groups settled"
  final int tripCount; // real trips → avg-per-trip divisor
  final List<Story> stories;
  // Derived-insight inputs, computed once in the shell (shared `now`). [alerts]
  // is the full severity-desc list (this tab caps display at 4); [pace] and
  // [budgetVnd] are null together when there's no active trip → both insight
  // cards are simply absent and the existing empty flow is untouched.
  final List<Alert> alerts;
  final TripPace? pace;
  final int? budgetVnd;

  /// Active trip's currency symbol (see core/logic/currency.dart) — every
  /// money figure this tab renders is scoped to that one trip.
  final String symbol;
  final List<BadgeProgress> badges;
  // Overview's Itinerary/Bookings/Budget chips jump straight to that My Trip
  // segment — owned by ProfileScreen since it also owns _tab.
  final ValueChanged<TripDetailSegment> onOpenTripSegment;
  // "View all →" on Saved Gems / Badges switches the main pill tab (2 Saved
  // Gems · 4 Badges) — same ProfileScreen-owned _tab as onOpenTripSegment.
  final ValueChanged<int> onSwitchTab;
  const _OverviewTab({
    required this.spent,
    required this.groups,
    required this.tripCount,
    required this.stories,
    required this.alerts,
    required this.pace,
    required this.budgetVnd,
    required this.symbol,
    required this.badges,
    required this.onOpenTripSegment,
    required this.onSwitchTab,
  });

  @override
  Widget build(BuildContext context) {
    final avg = tripCount > 0 ? spent / tripCount : 0;
    return MaxWidthCenter(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
        children: [
          // Next / upcoming trip pulse — first thing a returning user sees.
          _TripCarousel(onOpenTripSegment: onOpenTripSegment),
          const SizedBox(height: 16),

          // Derived alerts — most actionable, so directly under the trip pulse.
          // Absent when the active trip has nothing flagged.
          if (alerts.isNotEmpty) ...[
            _AlertsCard(
                alerts: alerts,
                symbol: symbol,
                onOpenTripSegment: onOpenTripSegment),
            const SizedBox(height: 16),
          ],

          // Budget pace — present for any active trip (honest not-started/no-budget
          // states included); absent only when there's no active trip.
          if (pace != null) ...[
            _PaceCard(pace: pace!, budgetVnd: budgetVnd ?? 0, symbol: symbol),
            const SizedBox(height: 16),
          ],

          // Expense summary
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeader(
                    icon: Icons.trending_up,
                    label: 'EXPENSE SUMMARY',
                    color: _kTeal),
                const SizedBox(height: 16),
                _summaryRow('Total across all trips',
                    '\$${spent.toStringAsFixed(1)}', _kInk),
                const SizedBox(height: 14),
                _summaryRow(
                    'Average per trip', '\$${avg.toStringAsFixed(2)}', _kInk),
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
                  ...stories.take(3).toList().asMap().entries.map(
                      (e) => _StoryRow(story: e.value, divider: e.key > 0)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Saved Gems — photo strip, matching the mockup. Bookmarked gems
          // (GemProvider.savedGems), not the user's own dropped pins — same
          // data the dedicated Saved Gems tab (index 2) reads.
          _SectionTitle(title: 'Saved Gems', onViewAll: () => onSwitchTab(2)),
          const SizedBox(height: 10),
          const _SavedGemsStrip(),
          const SizedBox(height: 20),

          // Badges — preview strip of the same _BadgeTile the Badges tab (index
          // 4) renders in full.
          _SectionTitle(title: 'Badges', onViewAll: () => onSwitchTab(4)),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: badges.isEmpty
                ? _emptyLine('No badges yet.')
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: badges.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(
                        width: 84, child: _BadgeTile(badge: badges[i])),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.fredoka(
                  fontSize: 15, color: const Color(0xFF555555))),
        ),
        Text(value,
            style: GoogleFonts.fredoka(
                fontSize: 17, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child:
            Text(text, style: GoogleFonts.fredoka(fontSize: 13, color: _kMute)),
      );
}

/// Section title + "View all →" link — the mockup's `.sec-head`/`.view-all`
/// pattern, used above the Saved Gems and Badges preview strips.
class _SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback onViewAll;
  const _SectionTitle({required this.title, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
        ),
        GestureDetector(
          onTap: onViewAll,
          child: Text('View all →',
              style: GoogleFonts.fredoka(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ),
      ],
    );
  }
}

/// Horizontal photo-strip preview of the user's bookmarked gems — reuses
/// [_SavedGemCard] (the Saved Gems tab's own card) so the two surfaces stay
/// visually identical.
class _SavedGemsStrip extends StatelessWidget {
  const _SavedGemsStrip();

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<GemProvider>().savedGems;
    if (saved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
            'Nothing saved yet — bookmark spots and they\'ll show up here.',
            style: GoogleFonts.fredoka(fontSize: 13, color: _kMute)),
      );
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: saved.length.clamp(0, 8),
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (_, i) =>
            SizedBox(width: 128, child: _SavedGemCard(gem: saved[i])),
      ),
    );
  }
}

// ─────────────────────────────────────────
// TRIP CAROUSEL (Overview)
// ─────────────────────────────────────────
/// Overview's trip pulse. Empty state (no trips ever) aside, this is a
/// left/right swipeable [PageView] over *every* trip the user owns — past and
/// upcoming — so trip count/detail is directly browsable from Overview
/// instead of only via the drawer's My Trips list. Segment chips (which jump
/// into the My Trip tab) only render on the active trip's page, since that
/// tab only ever reflects the single active trip — every other page just
/// links through to that trip's full summary on tap.
class _TripCarousel extends StatefulWidget {
  final ValueChanged<TripDetailSegment> onOpenTripSegment;
  const _TripCarousel({required this.onOpenTripSegment});

  @override
  State<_TripCarousel> createState() => _TripCarouselState();
}

class _TripCarouselState extends State<_TripCarousel> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    final provider = context.read<TripProvider>();
    final trips = provider.trips;
    final active = provider.activeTrip;
    var initial = 0;
    if (trips.isNotEmpty) {
      final activeIndex =
          active == null ? -1 : trips.indexWhere((t) => t.id == active.id);
      // No active trip means every trip is past — land on the most recent
      // one (trips sorts ascending by startDate) rather than the oldest.
      initial = activeIndex >= 0 ? activeIndex : trips.length - 1;
    }
    _page = initial;
    _controller = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final trips = provider.trips;
    final active = provider.activeTrip;

    // No trips ever: first-run nudge + chip CTA. No carousel to show.
    if (trips.isEmpty) {
      return _NextTripShell(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No trips yet',
                      style: GoogleFonts.fredoka(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kInk)),
                  const SizedBox(height: 2),
                  Text('Plan your first adventure.',
                      style: GoogleFonts.fredoka(fontSize: 13, color: _kMute)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _TripChipCta(
                label: '+ New trip', onTap: () => context.push('/trips/new')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 322,
          child: PageView.builder(
            controller: _controller,
            itemCount: trips.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _TripCard(
                trip: trips[i],
                isActive: active != null && trips[i].id == active.id,
                onOpenTripSegment: widget.onOpenTripSegment,
              ),
            ),
          ),
        ),
        if (trips.length > 1) ...[
          const SizedBox(height: 10),
          Center(child: _PageDots(count: trips.length, index: _page)),
        ],
      ],
    );
  }
}

/// One trip's hero card — full-bleed cover photo (or map-thumbnail/picsum
/// fallback) as the entire card's background, with a bottom-weighted scrim
/// and everything else — PAST/UPCOMING badge + day countdown, name, dates,
/// budget bar, and (active trip only) the Itinerary/Dashboard/Bookings
/// segment chips — layered directly over it. The single shared
/// implementation for both Overview's carousel and the My Trip tab's header
/// (trips_tab.dart calls this class directly; same library).
class _TripCard extends StatefulWidget {
  final Trip trip;
  final bool isActive;
  final ValueChanged<TripDetailSegment> onOpenTripSegment;
  const _TripCard(
      {required this.trip,
      required this.isActive,
      required this.onOpenTripSegment});

  @override
  State<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<_TripCard> {
  bool _openingExpenseSheet = false;

  Trip get trip => widget.trip;
  bool get isActive => widget.isActive;

  @override
  void initState() {
    super.initState();
    // Not preloaded elsewhere on Overview (only the active trip's bookings
    // are) — the avatar stack needs every shown card's own traveler list,
    // not just the active one. Idempotent/guarded inside the provider, so a
    // warm cache (e.g. this trip was already opened in My Trip) is a no-op.
    context.read<TripSetupProvider>().loadSetup(trip.id, ownerId: trip.ownerId);
  }

  /// Resolves this trip's shadow split group (auto-provisioning it on first
  /// use — see SplitsProvider.getOrCreateTripGroup) and this trip's
  /// traveler list (for the paid-by picker; not preloaded on Overview, so
  /// this loads it on demand), then opens the shared AddExpenseSheet
  /// pre-scoped to this trip — no group/trip picker, the user never sees
  /// "groups" at all.
  Future<void> _openAddExpense() async {
    if (_openingExpenseSheet) return;
    setState(() => _openingExpenseSheet = true);

    final splits = context.read<SplitsProvider>();
    final tripSetup = context.read<TripSetupProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final results = await Future.wait([
        splits.getOrCreateTripGroup(
            tripId: trip.id, tripName: trip.displayName),
        tripSetup.loadSetup(trip.id, ownerId: trip.ownerId).then((_) => null),
      ]);
      final groupId = results[0];
      if (!mounted) return;
      if (groupId == null) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Could not start this trip\'s expense group')),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => AddExpenseSheet(
          groupId: groupId,
          tripId: trip.id,
          travelers: tripSetup.travelersFor(trip.id),
          light: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingExpenseSheet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final spent = provider.totalSpent(trip.id);
    final symbol = currencyFor(trip.currency).symbol;
    final status = BudgetStatus.of(spent: spent, budgetVnd: trip.budgetVnd);
    final fill = (status.pct / 100).clamp(0.0, 1.0);

    final orderedStops = provider.allStopsOrdered(trip.id, trip.nights + 1);
    final gems = context.watch<GemProvider>().allGems;
    final travelers = context.watch<TripSetupProvider>().travelersFor(trip.id);

    // Full-bleed: the photo fills the entire card (not just a header strip),
    // with everything else — badges, title, dates, budget, segment chips —
    // layered on top of it as separate Stack siblings over _TripHeroPhoto's
    // own scrim. Buttons/avatars/chips each paint their own opaque
    // background, so tapping them is consumed there and never falls through
    // to _TripHeroPhoto's underlying map-tap GestureDetector beneath —
    // ordinary Stack hit-test behavior (topmost opaque hit wins), not
    // anything bespoke.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: SizedBox(
        height: 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TripHeroPhoto(trip: trip, orderedStops: orderedStops, gems: gems),
            Positioned(
              left: 15,
              right: 15,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(trip.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.bebasNeue(
                                fontSize: 22, color: Colors.white)),
                      ),
                      // Solo trip (organizer only) → nothing worth showing here;
                      // the stack only earns its space once there's an actual
                      // group. 2+ is the "worth showing" bar.
                      if (travelers.length > 1) ...[
                        _TravelerAvatarStack(
                          travelers: travelers,
                          onTap: () =>
                              widget.onOpenTripSegment(TripDetailSegment.trip),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: _openingExpenseSheet ? null : _openAddExpense,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primary,
                                Color.lerp(
                                    AppTheme.primary, Colors.white, 0.2)!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: _openingExpenseSheet
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add,
                                        size: 14, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text('Expense',
                                        style: GoogleFonts.fredoka(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Trip.formatDateRange(trip.startDate, trip.endDate)} · ${trip.nights} ${trip.nights == 1 ? 'night' : 'nights'}',
                    style: GoogleFonts.fredoka(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Budget used',
                            style: GoogleFonts.fredoka(
                                fontSize: 12, color: Colors.white)),
                      ),
                      Text(
                        '$symbol${Trip.formatVnd(spent, short: true)} ',
                        style: GoogleFonts.fredoka(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      Text(
                        '/ $symbol${Trip.formatVnd(trip.budgetVnd, short: true)}',
                        style: GoogleFonts.fredoka(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: Stack(
                      children: [
                        Container(
                            height: 6,
                            color: Colors.white.withValues(alpha: 0.25)),
                        FractionallySizedBox(
                          widthFactor: fill,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(100),
                              gradient: LinearGradient(colors: [
                                status.accent,
                                Color.lerp(status.accent, Colors.white, 0.3)!,
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                            child: _SegmentChip(
                                icon: Icons.calendar_today_outlined,
                                label: 'Itinerary',
                                onTap: () => widget.onOpenTripSegment(
                                    TripDetailSegment.itinerary))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _SegmentChip(
                                icon: Icons.attach_money,
                                label: 'Dashboard',
                                onTap: () => widget.onOpenTripSegment(
                                    TripDetailSegment.dashboard))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _SegmentChip(
                                icon: Icons.confirmation_number_outlined,
                                label: 'Bookings',
                                onTap: () => widget.onOpenTripSegment(
                                    TripDetailSegment.bookings))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact overlapping traveler avatars for the trip card header — up to
/// [_maxVisible], then a "+N" overflow bubble. Reuses _TravelerAvatar
/// (trips_tab.dart's Travelers card) at a smaller size rather than a
/// separate avatar treatment, so the two surfaces can't visually drift.
/// Tap jumps to the Trip tab's Travelers card — the same
/// onOpenTripSegment callback this card already uses for its Itinerary/
/// Dashboard/Bookings chips, so no new navigation surface either.
class _TravelerAvatarStack extends StatelessWidget {
  final List<TripTraveler> travelers;
  final VoidCallback onTap;
  const _TravelerAvatarStack({required this.travelers, required this.onTap});

  static const _maxVisible = 3;
  static const _size = 22.0;
  static const _overlap = 10.0; // each avatar covers this much of the previous

  @override
  Widget build(BuildContext context) {
    final shown = travelers.take(_maxVisible).toList();
    final extra = travelers.length - shown.length;
    final bubbleCount = shown.length + (extra > 0 ? 1 : 0);
    final width = _size + (bubbleCount - 1) * (_size - _overlap);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: _size,
        child: Stack(
          children: [
            for (final (i, t) in shown.indexed)
              Positioned(
                left: i * (_size - _overlap),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: _TravelerAvatar(traveler: t, size: _size),
                ),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (_size - _overlap),
                child: Container(
                  width: _size,
                  height: _size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text('+$extra',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dot-row page indicator — one dot per trip, filled orange for the current
/// page, so the trip count is visible at a glance without counting swipes.
class _PageDots extends StatelessWidget {
  final int count;
  final int index;
  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppTheme.primary : _kBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// Small overlay pill used on the hero photo (top-left "UPCOMING TRIP" tag,
/// top-right "N days to go" countdown).
/// Translucent glass pill for a badge layered directly over the hero photo —
/// blurred so it stays legible over any part of the image, not just a
/// pre-darkened region.
class _HeroBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const _HeroBadge(
      {required this.label,
      required this.background,
      required this.foreground});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: foreground,
                letterSpacing: 0.4),
          ),
        ),
      ),
    );
  }
}

/// One of the hero card's three shortcuts into the My Trip tab's segments.
/// Semi-transparent dark pill (not a light card) — it sits directly over the
/// full-bleed cover photo, not a separate light section beneath it.
class _SegmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SegmentChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 17, color: Colors.white),
            const SizedBox(height: 6),
            Text(label,
                style: GoogleFonts.fredoka(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// picsum.photos seed for the hero photo fallback — same house convention as
/// destination_provider.dart's placeholder destination photos, keyed by the
/// trip's free-text location since there's no real cover-photo field.
String _locationSlug(String location) =>
    location.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// The trip's real, user-uploaded cover photo when it has one (set via the
/// setup wizard's Cover Image field or EditTripSheet); otherwise a real map
/// centered on the trip's destination when it has coordinates (picked from
/// the setup wizard's place autocomplete), with the itinerary's stops
/// plotted as a numbered route when any are plottable; the picsum.photos
/// placeholder otherwise — older trips, free-typed locations, a missing
/// Mapbox token, and a trip with no plottable stops all fall back the same
/// way rather than showing a broken/bare image.
String _heroImageUrl(Trip trip, List<TripStop> orderedStops, List<Gem> gems) {
  final cover = trip.coverImageUrl;
  if (cover != null && cover.isNotEmpty) return cover;
  final lat = trip.locationLat, lng = trip.locationLng;
  if (lat != null && lng != null) {
    final overlay = _routeOverlay(orderedStops, gems);
    final mapUrl = GeocodingService.staticImageUrl(
      lat: lat,
      lng: lng,
      overlay: overlay,
      // Frame to the route when there's one to show — a fixed city-level
      // zoom around the destination point wouldn't reliably keep every stop
      // in frame. Falls back to the plain centered/zoomed destination map
      // when there's nothing plottable (overlay null).
      autoFit: overlay != null,
    );
    if (mapUrl != null) return mapUrl;
  }
  return 'https://picsum.photos/seed/${_locationSlug(trip.location)}/800/400';
}

/// Full-bleed background layer for [_TripCard]: cover photo (or
/// map-thumbnail/picsum fallback, via [_heroImageUrl]) with a bottom-weighted
/// scrim and PAST/UPCOMING + day-countdown badges, tapping through to the
/// full itinerary map ([TripMapDialog]). Fills whatever size its parent
/// Stack gives it — [_TripCard] is the sole caller (both Overview's carousel
/// and the My Trip tab's header use [_TripCard] itself, not this directly;
/// same library, both `part of` profile_screen.dart).
class _TripHeroPhoto extends StatelessWidget {
  const _TripHeroPhoto({
    required this.trip,
    required this.orderedStops,
    required this.gems,
  });

  final Trip trip;
  final List<TripStop> orderedStops;
  final List<Gem> gems;

  @override
  Widget build(BuildContext context) {
    final daysUntil = trip.daysUntilStart;
    final isPast = daysUntil < 0;

    return GestureDetector(
      // Centered modal (dimmed backdrop, tap-outside/X to dismiss) — not a
      // routed screen, so this is a showDialog, not a push. Safe even for a
      // brand-new trip with no stops yet: TripMapDialog's own _TripMapView
      // renders an "No stops planned yet" empty state rather than erroring.
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => TripMapDialog(tripId: trip.id),
      ),
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppNetworkImage(
              url: _heroImageUrl(trip, orderedStops, gems),
              fit: BoxFit.cover,
              semanticLabel: trip.location,
            ),
            // Full-bleed cards carry all their text/buttons over the photo
            // now, not just a couple of badges over a thin strip — a flat
            // 0.05→0.55 wash left the lower half (title/budget/segment
            // chips) too weak against bright photos. Three stops instead of
            // two: the top stays nearly clear (badges already sit on their
            // own opaque pills), then darkens steeply from ~40% down so the
            // whole content zone stays legible regardless of the photo's own
            // brightness/color.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 11,
              child: _HeroBadge(
                label: isPast ? 'PAST TRIP' : 'UPCOMING TRIP',
                background: Colors.black.withValues(alpha: 0.72),
                foreground: AppTheme.primary,
              ),
            ),
            Positioned(
              right: 12,
              top: 11,
              child: _HeroBadge(
                label:
                    isPast ? '${-daysUntil} days ago' : '$daysUntil days to go',
                background: AppTheme.primary,
                foreground: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stops per card before the map switches from one-pin-per-stop to
/// one-pin-per-day — keeps a long trip's card from rendering an unreadable
/// cluster of overlapping numbers. The full-screen trip map (trip_map_dialog.dart)
/// uses [plotStops] uncapped instead, per its own "don't simplify" brief.
const int _kMaxPinsPerCard = 10;

/// Builds the color-coded-by-day pin + route overlay for the map card, or
/// null when nothing is plottable (empty trip, or every stop is custom/
/// coordinate-less) — callers fall back to the plain destination map in that
/// case. Simplified relative to the full map modal: colored pins and colored
/// per-day route lines only — no direction arrows or "DAY N" chips, since
/// the Mapbox Static Images API this card renders through has no equivalent
/// of either (and neither would read at thumbnail scale anyway).
String? _routeOverlay(List<TripStop> orderedStops, List<Gem> gems) {
  final plotted = plotStops(orderedStops, gems, maxPins: _kMaxPinsPerCard);
  if (plotted.isEmpty) return null;

  final pins = [
    for (final p in plotted)
      (
        lat: p.lat,
        lng: p.lng,
        label: p.label,
        color: GeocodingService.hexFromArgb(colorForTripDay(p.stop.day)),
      ),
  ];
  final byDay = groupPlottedByDay(plotted);
  final routes = [
    for (final day in byDay.keys)
      (
        points: [for (final p in byDay[day]!) (lat: p.lat, lng: p.lng)],
        color: GeocodingService.hexFromArgb(colorForTripDay(day)),
      ),
  ];
  return GeocodingService.buildStaticMapOverlay(pins: pins, routes: routes);
}

/// Compact card chrome for [_TripCarousel]'s no-trips-ever empty state — same
/// fill/border/radius as [_Card] but tuned padding for the denser trip content.
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

/// Small pill CTA used by [_TripCarousel]'s no-trips-ever first-run state.
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
            style: GoogleFonts.fredoka(
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
/// Which My Trip segment an alert's CTA jumps to — every kind maps to the
/// segment that actually resolves it (a booking gap → Bookings, an overrun
/// category → Dashboard's category breakdown, a booking coming due →
/// Bookings again).
TripDetailSegment _alertSegment(AlertKind k) => switch (k) {
      AlertKind.unbookedStop => TripDetailSegment.bookings,
      AlertKind.overBudgetCategory => TripDetailSegment.dashboard,
      AlertKind.upcomingBooking => TripDetailSegment.bookings,
    };

String _alertCta(AlertKind k) => switch (k) {
      AlertKind.unbookedStop => 'Book now',
      AlertKind.overBudgetCategory => 'Review',
      AlertKind.upcomingBooking => 'View',
    };

class _AlertsCard extends StatelessWidget {
  final List<Alert> alerts;
  final String symbol;
  final ValueChanged<TripDetailSegment> onOpenTripSegment;
  const _AlertsCard(
      {required this.alerts,
      required this.symbol,
      required this.onOpenTripSegment});

  static const int _kAlertCap = 4;

  @override
  Widget build(BuildContext context) {
    final shown = alerts.take(_kAlertCap).toList();
    final extra = alerts.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Needs attention',
            style: GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
        const SizedBox(height: 10),
        for (final a in shown) ...[
          _AlertRow(
              alert: a, symbol: symbol, onOpenTripSegment: onOpenTripSegment),
          const SizedBox(height: 10),
        ],
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+$extra more',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: _kMute, letterSpacing: 0.5)),
          ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  final Alert alert;
  final String symbol;
  final ValueChanged<TripDetailSegment> onOpenTripSegment;
  const _AlertRow(
      {required this.alert,
      required this.symbol,
      required this.onOpenTripSegment});

  @override
  Widget build(BuildContext context) {
    final accent = _alertAccent(alert.severity);
    final copy = _alertCopy(alert, symbol);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_alertIcon(alert.kind), size: 17, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy.title,
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kInk)),
                const SizedBox(height: 2),
                Text(copy.body,
                    style: GoogleFonts.fredoka(
                        fontSize: 12.5, color: _kMute, height: 1.35)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => onOpenTripSegment(_alertSegment(alert.kind)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _kPage,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: Text(_alertCta(alert.kind),
                        style: GoogleFonts.fredoka(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accent)),
                  ),
                ),
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
({String title, String body}) _alertCopy(Alert a, String symbol) {
  switch (a.kind) {
    case AlertKind.unbookedStop:
      final price = a.payload['priceVnd'] ?? 0;
      return (
        title: 'Nothing booked yet',
        body: price > 0
            ? '$symbol${Trip.formatVnd(price, short: true)} planned — no booking against it.'
            : 'A planned stop has no booking yet.',
      );
    case AlertKind.overBudgetCategory:
      final over = a.payload['overVnd'] ?? 0;
      final actual = a.payload['actualVnd'] ?? 0;
      final planned = a.payload['plannedVnd'] ?? 0;
      final cat = _capitalize(a.category);
      return (
        title: '$cat over budget',
        body: '$symbol${Trip.formatVnd(actual, short: true)} of '
            '$symbol${Trip.formatVnd(planned, short: true)} · '
            '$symbol${Trip.formatVnd(over, short: true)} over.',
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
  final String symbol;
  const _PaceCard(
      {required this.pace, required this.budgetVnd, required this.symbol});

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
              'Day 0 of ${pace.tripDays} · $symbol${Trip.formatVnd(budgetVnd, short: true)} planned'),
        ];
      case PaceStatus.noBudget:
        return [
          _headline('No budget set', _kInk),
          const SizedBox(height: 4),
          _mono(
              '$symbol${Trip.formatVnd(pace.cumulativeActual, short: true)} committed so far'),
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
        '$symbol${Trip.formatVnd(pace.delta, short: true)} over pace',
      PaceStatus.underPace =>
        '$symbol${Trip.formatVnd(pace.delta.abs(), short: true)} under pace',
      _ => 'On pace',
    };
    final actualFill = budgetVnd > 0
        ? (pace.cumulativeActual / budgetVnd).clamp(0.0, 1.0)
        : 0.0;
    final expectedFill = budgetVnd > 0
        ? (pace.expectedByToday / budgetVnd).clamp(0.0, 1.0)
        : 0.0;
    return [
      Row(
        children: [
          Expanded(
              child: _mono('Day ${pace.tripDayToday} of ${pace.tripDays}')),
          Text(deltaText,
              style: GoogleFonts.fredoka(
                  fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
        ],
      ),
      const SizedBox(height: 10),
      // Actual-fill bar + expected-position tick. Same Stack idiom as
      // _TripCard's budget bar; the tick is Aligned by fraction (−1..1).
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
      style: GoogleFonts.fredoka(
          fontSize: 15, fontWeight: FontWeight.w800, color: c));

  Widget _mono(String t) => Text(t,
      style: GoogleFonts.jetBrainsMono(
          fontSize: 11, color: _kMute, letterSpacing: 0.3));
}

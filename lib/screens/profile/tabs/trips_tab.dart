part of '../profile_screen.dart';

// My Trip tab: full itinerary-management surface — switch between any trip,
// manage days (add/delete/duplicate), manage activities within a day
// (edit/delete/reorder) — all without leaving the profile screen. Adding a
// *new* activity, though, hands off to Trip Builder (/trips/:id/builder?day=N)
// rather than a local quick-add sheet — that's the one surface with the gem
// picker + drag-drop, and duplicating it here would drift the two out of sync.

// ─────────────────────────────────────────
// MY TRIP TAB
// ─────────────────────────────────────────

/// The four My Trip segments, left to right. `label` drives both the
/// [_SegmentedControl] chip text and stays the single source of truth for
/// ordering — nothing outside this enum hardcodes a position, so reordering
/// (or inserting a 5th segment) can't silently desync a caller the way the
/// old bare-int `_segment` could (three call sites hardcoded 0/1/2).
///
/// `dashboard` (was `budget`) was moved before `bookings` and renamed —
/// confirmed order: Trip | Itinerary | Dashboard | Bookings. It replaces the
/// old Budget segment's content entirely (see _DashboardSegment in
/// trips_tab.dart) rather than sitting alongside it as a 5th segment.
enum TripDetailSegment {
  trip,
  itinerary,
  dashboard,
  bookings;

  String get label => switch (this) {
        TripDetailSegment.trip => 'Trip',
        TripDetailSegment.itinerary => 'Itinerary',
        TripDetailSegment.dashboard => 'Dashboard',
        TripDetailSegment.bookings => 'Bookings',
      };
}

/// My Trip's compact, non-scrolling header: title/dates condensed to one
/// line (no separate hero photo/badges — that's Overview's carousel card,
/// _TripCard in overview_tab.dart, a distinct widget from this one), the
/// trip switcher/edit/map icons inline with the title, and the existing
/// list-all-trips/+New-Trip controls trailing. Replaces what used to be
/// _TripCard + a separate utility row on this tab — see the map icon's doc
/// comment below for why the itinerary-map shortcut lives here now, and
/// _DashboardSegment's "+ Add Expense" for where the expense shortcut went.
class _TripCompactHeader extends StatelessWidget {
  const _TripCompactHeader({
    required this.trip,
    required this.onSwitch,
    required this.onEdit,
    required this.onOpenMap,
    required this.onList,
    required this.onNewTrip,
  });

  final Trip trip;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onOpenMap;
  final VoidCallback onList;
  final VoidCallback onNewTrip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '${trip.displayName} · ${Trip.formatDateRange(trip.startDate, trip.endDate)} · ${trip.nights} ${trip.nights == 1 ? 'night' : 'nights'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bebasNeue(fontSize: 19, color: _kInk),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onSwitch,
                child: const Icon(Icons.expand_more, size: 22, color: _kMute),
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(Icons.edit_outlined, size: 16, color: _kMute),
              ),
              const SizedBox(width: 6),
              // The hero card's tap-to-open-map shortcut moved here — no
              // photo to tap anymore, so it's a small explicit icon instead.
              GestureDetector(
                onTap: onOpenMap,
                child: const Icon(Icons.map_outlined, size: 18, color: _kMute),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onList,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: const Icon(Icons.list_alt_outlined, size: 19, color: _kInk),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onNewTrip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('+ New Trip',
                style: GoogleFonts.fredoka(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _MyTripTab extends StatefulWidget {
  final Trip? trip; // the account's active trip, or null
  // Which segment to open on — set by Overview's chip taps
  // (ProfileScreen._openMyTrip); defaults to Itinerary when the tab is
  // reached any other way (its own pill, direct tab-bar tap) — Trip sits
  // leftmost visually, but Itinerary stays the landing default.
  final TripDetailSegment initialSegment;
  // Which trip to land on — set from a ProfileDeepLink (e.g. Trip Builder's
  // back button) so a non-active trip is selected on arrival. Null falls
  // through to the active-trip/first-trip default below.
  final String? initialTripId;
  const _MyTripTab(
      {required this.trip,
      this.initialSegment = TripDetailSegment.itinerary,
      this.initialTripId});

  @override
  State<_MyTripTab> createState() => _MyTripTabState();
}

class _MyTripTabState extends State<_MyTripTab> {
  late TripDetailSegment _segment = widget.initialSegment;
  // Which trip the switcher has picked, if any — null means "follow the
  // active trip" (widget.trip). Kept as an id (not a Trip snapshot) so an
  // edit elsewhere (e.g. EditTripSheet) is reflected immediately via a fresh
  // TripProvider.tripById lookup each build, rather than going stale.
  late String? _selectedTripId = widget.initialTripId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    if (provider.trips.isEmpty) {
      return _EmptyState(
        icon: Icons.map_outlined,
        title: 'No active trip',
        subtitle: 'Plan your next trip to see it here.',
        cta: 'Plan a trip',
        onTap: () => context.push('/trips/new'),
      );
    }

    final trip = provider.tripById(_selectedTripId ?? '') ??
        widget.trip ??
        provider.trips.first;

    // Fixed header + segmented control, scrolling body: unlike Overview's
    // carousel card (a quick-glance shortcut), My Trip is a workspace — the
    // header/tabs are navigation chrome the user wants available at a
    // glance, not content to scroll past. Only the active segment's content
    // (day-rail/itinerary, travelers, dashboard, bookings) scrolls, so a
    // typical phone screen shows real itinerary content without scrolling.
    return MaxWidthCenter(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: _TripCompactHeader(
              trip: trip,
              onSwitch: () => _openSwitcher(trip.id),
              onEdit: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => EditTripSheet(trip: trip),
              ),
              onOpenMap: () => showDialog<void>(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.6),
                builder: (_) => TripMapDialog(tripId: trip.id),
              ),
              onList: () => context.go('/trips'),
              onNewTrip: () => context.push('/trips/new'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SegmentedControl(
              labels: [for (final s in TripDetailSegment.values) s.label],
              active: _segment.index,
              onSelect: (i) =>
                  setState(() => _segment = TripDetailSegment.values[i]),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              children: [
                switch (_segment) {
                  TripDetailSegment.trip => _TripSegment(trip: trip),
                  TripDetailSegment.itinerary => _ItinerarySegment(trip: trip),
                  TripDetailSegment.dashboard => _DashboardSegment(trip: trip),
                  TripDetailSegment.bookings => _BookingsSegment(trip: trip),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSwitcher(String currentId) {
    showTripSwitcherSheet(
      context,
      currentTripId: currentId,
      onSelect: (id) => setState(() => _selectedTripId = id),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int active;
  final ValueChanged<int> onSelect;
  const _SegmentedControl(
      {required this.labels, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == active
                        ? [
                            BoxShadow(
                                color: _kInk.withValues(alpha: 0.10),
                                blurRadius: 4,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fredoka(
                      fontSize: 12,
                      fontWeight:
                          i == active ? FontWeight.w700 : FontWeight.w500,
                      color: i == active ? _kInk : _kMute,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// TRIP SEGMENT
// ─────────────────────────────────────────
/// Canary placeholder — proves the enum/index wiring (segment order, chip
/// taps, default-landing-segment) end to end before the three real cards
/// (Travelers/Documents/Packing) land on top of it.
class _TripSegment extends StatefulWidget {
  final Trip trip;
  const _TripSegment({required this.trip});

  @override
  State<_TripSegment> createState() => _TripSegmentState();
}

class _TripSegmentState extends State<_TripSegment> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TripSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The switcher sheet can swap `trip` without unmounting this widget (same
    // Element, new Trip) — a fresh initState never fires, so the reload has
    // to be driven from here instead.
    if (oldWidget.trip.id != widget.trip.id) _load();
  }

  void _load() => context
      .read<TripSetupProvider>()
      .loadSetup(widget.trip.id, ownerId: widget.trip.ownerId);

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<TripSetupProvider>();
    final travelers = setup.travelersFor(widget.trip.id);
    final documents = setup.documentsFor(widget.trip.id);
    final packing = setup.packingFor(widget.trip.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CardHeader(
            icon: Icons.groups_outlined,
            label: 'TRAVELERS',
            color: AppTheme.primary),
        const SizedBox(height: 10),
        _TravelersCard(tripId: widget.trip.id, travelers: travelers),
        const SizedBox(height: 16),
        const _CardHeader(
            icon: Icons.description_outlined,
            label: 'DOCUMENTS',
            color: _kTeal),
        const SizedBox(height: 10),
        _DocumentsCard(
            trip: widget.trip, documents: documents, travelers: travelers),
        const SizedBox(height: 16),
        const _CardHeader(
            icon: Icons.checklist_outlined, label: 'PACKING', color: _kGreen),
        const SizedBox(height: 10),
        _PackingCard(
            tripId: widget.trip.id, items: packing, travelers: travelers),
      ],
    );
  }
}

/// Rows: avatar, name + role subtitle (Organizer/Member), status pill
/// (Confirmed → green, Invited → amber). One row per [TripTraveler] — the
/// Organizer row is always first (TripSetupProvider.loadSetup puts it there).
class _TravelersCard extends StatelessWidget {
  final String tripId;
  final List<TripTraveler> travelers;
  const _TravelersCard({required this.tripId, required this.travelers});

  void _openLookup(BuildContext context) {
    final excludeIds = {for (final t in travelers) t.userId};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TravelerLookupSheet(
        excludeUserIds: excludeIds,
        onSelect: (profile) {
          context.read<TripSetupProvider>().addTraveler(
                tripId: tripId,
                userId: profile.id,
                displayName: profile.displayName,
                avatarUrl: profile.avatarUrl,
              );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (travelers.isEmpty)
          // loadSetup hasn't resolved yet (or the trip somehow has no owner
          // profile) — a bare _Card rather than the full _EmptyState
          // treatment, since this is a transient loading gap, not a real
          // empty state (every trip has at least an Organizer once loaded).
          const _Card(child: SizedBox(height: 40))
        else
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, t) in travelers.indexed)
                  _TravelerRow(traveler: t, divider: i > 0),
              ],
            ),
          ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _openLookup(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('+ Add Traveler',
                style: GoogleFonts.fredoka(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kMute)),
          ),
        ),
      ],
    );
  }
}

class _TravelerRow extends StatelessWidget {
  final TripTraveler traveler;
  final bool divider;
  const _TravelerRow({required this.traveler, required this.divider});

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        traveler.role == TravelerRole.organizer ? 'Organizer' : 'Member';
    final confirmed = traveler.status == TravelerStatus.confirmed;
    final pillColor = confirmed ? _kGreen : _kWarn;
    final pillLabel = confirmed ? 'CONFIRMED' : 'INVITED';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider ? const Border(top: BorderSide(color: _kBorder)) : null,
      ),
      child: Row(
        children: [
          _TravelerAvatar(traveler: traveler),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(traveler.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk)),
                const SizedBox(height: 2),
                Text(roleLabel,
                    style: GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: pillColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(pillLabel,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: pillColor,
                    letterSpacing: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// Circular avatar (36px by default); falls back to initials-on-tint when
/// there's no [TripTraveler.avatarUrl] (AppNetworkImage requires a non-null
/// url, so the fallback branches before ever constructing it). [size] is
/// configurable — the Packing card's assignee avatar rides alongside a
/// checkbox and a close button, so it uses a smaller one than the full-width
/// Travelers row does.
class _TravelerAvatar extends StatelessWidget {
  final TripTraveler traveler;
  final double size;
  const _TravelerAvatar({required this.traveler, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final url = traveler.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: AppNetworkImage(url: url, width: size, height: size),
      );
    }
    final initials = traveler.displayName.trim().isEmpty
        ? '?'
        : traveler.displayName.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(initials,
          style: GoogleFonts.fredoka(
              fontSize: size * 0.39,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary)),
    );
  }
}

// ─────────────────────────────────────────
// DOCUMENTS
// ─────────────────────────────────────────

/// Alert chip for a document row, or null when it needs none. Pure — no
/// context/widget dependency, unit-testable in isolation. Two rules,
/// evaluated in severity order:
///   - a passport expiring less than 6 months after the trip's end date (the
///     common "6-month validity" entry requirement) → critical. A passport
///     that clears this bar can't also trip the second rule below (clearing
///     it means the expiry is at least 6 months past trip end, which is
///     already well outside the trip window) — so returning here is
///     exhaustive for passports, not just an early-exit shortcut.
///   - any document (any type) whose expiry falls inside the trip's own
///     date window → warn ("you'll be relying on it after it's void").
({String label, Color color})? _expiryAlertFor(TripDocument doc, Trip trip) {
  final expiresOn = doc.expiresOn;
  if (expiresOn == null) return null;

  if (doc.type == DocumentType.passport) {
    final sixMoAfterEnd =
        DateTime(trip.endDate.year, trip.endDate.month + 6, trip.endDate.day);
    if (expiresOn.isBefore(sixMoAfterEnd)) {
      return (label: '6-MO RULE', color: _kCritical);
    }
  }

  final start =
      DateTime(trip.startDate.year, trip.startDate.month, trip.startDate.day);
  final end = DateTime(trip.endDate.year, trip.endDate.month, trip.endDate.day);
  final expiry = DateTime(expiresOn.year, expiresOn.month, expiresOn.day);
  if (!expiry.isBefore(start) && !expiry.isAfter(end)) {
    return (label: 'ENDS MID-TRIP', color: _kWarn);
  }
  return null;
}

String _documentTypeLabel(DocumentType t) => switch (t) {
      DocumentType.passport => 'Passport',
      DocumentType.visa => 'Visa',
      DocumentType.ticket => 'Ticket',
      DocumentType.reservation => 'Reservation',
      DocumentType.insurance => 'Insurance',
    };

String _fmtDocDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

class _DocumentsCard extends StatelessWidget {
  final Trip trip;
  final List<TripDocument> documents;
  final List<TripTraveler> travelers;
  const _DocumentsCard(
      {required this.trip, required this.documents, required this.travelers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (documents.isEmpty)
          const _EmptyState(
            icon: Icons.description_outlined,
            title: 'No documents yet',
            subtitle:
                'Passports, visas, tickets, and reservations you add will show up here.',
          )
        else
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, d) in documents.indexed)
                  _DocumentRow(
                      document: d,
                      trip: trip,
                      travelers: travelers,
                      divider: i > 0),
              ],
            ),
          ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _AddDocumentSheet(tripId: trip.id),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('+ Add Document',
                style: GoogleFonts.fredoka(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kMute)),
          ),
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final TripDocument document;
  final Trip trip;
  final List<TripTraveler> travelers;
  final bool divider;
  const _DocumentRow(
      {required this.document,
      required this.trip,
      required this.travelers,
      required this.divider});

  @override
  Widget build(BuildContext context) {
    final alert = _expiryAlertFor(document, trip);
    final ownerId = document.ownerCollaboratorId;
    final ownerLabel = ownerId == null
        ? 'Shared'
        : travelers.where((t) => t.id == ownerId).firstOrNull?.displayName ??
            'Traveler';
    final subtitle = '${_documentTypeLabel(document.type)} · $ownerLabel';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider ? const Border(top: BorderSide(color: _kBorder)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                if (document.expiresOn != null) ...[
                  const SizedBox(height: 2),
                  Text('Expires ${_fmtDocDate(document.expiresOn!)}',
                      style: GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                ],
                if (alert != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: alert.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(alert.label,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: alert.color,
                            letterSpacing: 0.6)),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<TripSetupProvider>().removeDocument(document.id);
            },
            icon: const Icon(Icons.close, size: 18, color: _kMute),
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _AddDocumentSheet extends StatefulWidget {
  final String tripId;
  const _AddDocumentSheet({required this.tripId});

  @override
  State<_AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<_AddDocumentSheet> {
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  DocumentType _type = DocumentType.passport;
  DateTime? _expiresOn;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresOn ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _expiresOn = picked);
  }

  // Fire-and-forget — addDocument is optimistic and self-rolls-back on
  // error, same convention as TimeSlotBlock's addStop / _ActivityEditSheet's
  // updateStopDetails. No local loading state to manage.
  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    context.read<TripSetupProvider>().addDocument(
          tripId: widget.tripId,
          type: _type,
          title: title,
          fileUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          expiresOn: _expiresOn,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: _kBorder, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add document',
                        style:
                            GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in DocumentType.values)
                          _TypeChip(
                            label: _documentTypeLabel(t),
                            selected: t == _type,
                            onTap: () => setState(() => _type = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Title'),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickExpiry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder)),
                        child: Row(children: [
                          const Icon(Icons.event_outlined,
                              size: 18, color: _kMute),
                          const SizedBox(width: 10),
                          Text(
                              _expiresOn == null
                                  ? 'Expiry date (optional)'
                                  : _fmtDocDate(_expiresOn!),
                              style: GoogleFonts.fredoka(
                                  fontSize: 14,
                                  color: _expiresOn == null ? _kMute : _kInk)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Link (optional)'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Save',
                          style: GoogleFonts.fredoka(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppTheme.primary : _kBorder),
        ),
        child: Text(label,
            style: GoogleFonts.fredoka(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _kMute)),
      ),
    );
  }
}

// ─────────────────────────────────────────
// PACKING
// ─────────────────────────────────────────
class _PackingCard extends StatelessWidget {
  final String tripId;
  final List<PackingItem> items;
  final List<TripTraveler> travelers;
  const _PackingCard(
      {required this.tripId, required this.items, required this.travelers});

  @override
  Widget build(BuildContext context) {
    final packed = items.where((i) => i.isPacked).length;
    final total = items.length;
    final fill = total == 0 ? 0.0 : packed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty) ...[
          Text('$packed / $total packed',
              style: GoogleFonts.fredoka(
                  fontSize: 12, color: _kMute, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 6, color: _kBorder),
                FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(height: 6, color: _kGreen)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (items.isEmpty)
          const _EmptyState(
            icon: Icons.checklist_outlined,
            title: 'Nothing packed yet',
            subtitle: 'Add items to build out the packing list.',
          )
        else
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, item) in items.indexed)
                  _PackingRow(item: item, travelers: travelers, divider: i > 0),
              ],
            ),
          ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                _AddPackingItemSheet(tripId: tripId, travelers: travelers),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('+ Add Item',
                style: GoogleFonts.fredoka(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kMute)),
          ),
        ),
      ],
    );
  }
}

class _PackingRow extends StatelessWidget {
  final PackingItem item;
  final List<TripTraveler> travelers;
  final bool divider;
  const _PackingRow(
      {required this.item, required this.travelers, required this.divider});

  @override
  Widget build(BuildContext context) {
    final assigneeId = item.assigneeCollaboratorId;
    final assignee = assigneeId == null
        ? null
        : travelers.where((t) => t.id == assigneeId).firstOrNull;
    final subtitleParts = <String>[
      if (item.quantity > 1) '×${item.quantity}',
      if ((item.category ?? '').isNotEmpty) item.category!,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: divider ? const Border(top: BorderSide(color: _kBorder)) : null,
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              context.read<TripSetupProvider>().togglePacked(item.id);
            },
            child: Icon(
              item.isPacked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: item.isPacked ? _kGreen : _kMute,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: item.isPacked ? _kMute : _kInk,
                      decoration:
                          item.isPacked ? TextDecoration.lineThrough : null,
                    )),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitleParts.join(' · '),
                      style: GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                ],
              ],
            ),
          ),
          if (assignee != null) ...[
            const SizedBox(width: 8),
            _TravelerAvatar(traveler: assignee, size: 26),
          ],
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<TripSetupProvider>().removePackingItem(item.id);
            },
            icon: const Icon(Icons.close, size: 18, color: _kMute),
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _AddPackingItemSheet extends StatefulWidget {
  final String tripId;
  final List<TripTraveler> travelers;
  const _AddPackingItemSheet({required this.tripId, required this.travelers});

  @override
  State<_AddPackingItemSheet> createState() => _AddPackingItemSheetState();
}

class _AddPackingItemSheetState extends State<_AddPackingItemSheet> {
  final _labelCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  int _quantity = 1;
  // null = unassigned/shared. The organizer is a valid target too — the
  // owner has a real trip_collaborators row (see TripSetupProvider.loadSetup
  // class doc), so their `id` is as FK-able as any member's.
  String? _assigneeCollaboratorId;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _adjustQuantity(int delta) =>
      setState(() => _quantity = (_quantity + delta).clamp(1, 99));

  // Fire-and-forget — same convention as _AddDocumentSheet._save.
  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    context.read<TripSetupProvider>().addPackingItem(
          tripId: widget.tripId,
          assigneeCollaboratorId: _assigneeCollaboratorId,
          label: label,
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          quantity: _quantity,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: _kBorder, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add packing item',
                        style:
                            GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _labelCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Item'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _categoryCtrl,
                            style:
                                GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                            decoration:
                                _lightFieldDecoration('Category (optional)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _QuantityStepper(
                            quantity: _quantity, onAdjust: _adjustQuantity),
                      ],
                    ),
                    if (widget.travelers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TypeChip(
                            label: 'Unassigned',
                            selected: _assigneeCollaboratorId == null,
                            onTap: () =>
                                setState(() => _assigneeCollaboratorId = null),
                          ),
                          for (final t in widget.travelers)
                            _TypeChip(
                              label: t.displayName,
                              selected: _assigneeCollaboratorId == t.id,
                              onTap: () => setState(
                                  () => _assigneeCollaboratorId = t.id),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Save',
                          style: GoogleFonts.fredoka(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onAdjust;
  const _QuantityStepper({required this.quantity, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => onAdjust(-1),
            icon: const Icon(Icons.remove, size: 16, color: _kMute),
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 20,
            child: Text('$quantity',
                textAlign: TextAlign.center,
                style: GoogleFonts.fredoka(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _kInk)),
          ),
          IconButton(
            onPressed: () => onAdjust(1),
            icon: const Icon(Icons.add, size: 16, color: _kMute),
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// ITINERARY SEGMENT
// ─────────────────────────────────────────
/// One collapsible card per day (1..dayCount), each grouping its stops into
/// Morning/Afternoon/Evening sections (matching Trip Builder's own slot
/// structure) under a planned-time/planned-cost summary strip. Day count is
/// derived from the trip's start/end dates ([Trip.nights] + 1);
/// Add/Delete/Duplicate Day mutate those dates via TripProvider rather than
/// an independent "day" concept.
class _ItinerarySegment extends StatefulWidget {
  final Trip trip;
  const _ItinerarySegment({required this.trip});

  @override
  State<_ItinerarySegment> createState() => _ItinerarySegmentState();
}

class _ItinerarySegmentState extends State<_ItinerarySegment> {
  int _activeDay = 1;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final dayCount = trip.nights + 1;
    final gemsById = {
      for (final g in context.watch<GemProvider>().allGems) g.id: g,
    };
    final bookings = context.watch<BookingProvider>().bookingsFor(trip.id);
    // Whole-trip stops (not just this day's) — the Edit Booking sheet reopened
    // from a chip/banner tap needs the full list for its stop picker, same as
    // the Bookings tab itself.
    final allStops =
        context.watch<TripProvider>().allStopsOrdered(trip.id, dayCount);
    final safeDay = _activeDay.clamp(1, dayCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayRail(
          trip: trip,
          dayCount: dayCount,
          activeDay: safeDay,
          onSelect: (day) => setState(() => _activeDay = day),
          onAddDay: () async {
            await context.read<TripProvider>().addDay(trip.id);
            setState(() => _activeDay = dayCount + 1); // land on the new day
          },
        ),
        const SizedBox(height: 12),
        _DayPanel(
          trip: trip,
          day: safeDay,
          dayCount: dayCount,
          gemsById: gemsById,
          bookings: bookings,
          allStops: allStops,
        ),
      ],
    );
  }
}

/// Horizontal day-chip rail — tap a day to switch the panel below, matching
/// Trip Builder's own `_DayChipStrip` (itinerary_canvas.dart) so the two
/// surfaces navigate days identically. A trailing "+" chip extends the trip
/// by a day (TripProvider.addDay) rather than living as a separate button.
class _DayRail extends StatelessWidget {
  final Trip trip;
  final int dayCount;
  final int activeDay;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddDay;
  const _DayRail({
    required this.trip,
    required this.dayCount,
    required this.activeDay,
    required this.onSelect,
    required this.onAddDay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dayCount + 1, // + the trailing add-day chip
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == dayCount) return _AddDayChip(onTap: onAddDay);
          final day = i + 1;
          final date = trip.startDate.add(Duration(days: day - 1));
          return _DayRailChip(
            date: date,
            active: day == activeDay,
            onTap: () => onSelect(day),
          );
        },
      ),
    );
  }
}

class _DayRailChip extends StatelessWidget {
  final DateTime date;
  final bool active;
  final VoidCallback onTap;
  const _DayRailChip(
      {required this.date, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppTheme.primary : _kBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_weekdayAbbr[date.weekday - 1],
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: active
                        ? Colors.white.withValues(alpha: 0.85)
                        : _kMute)),
            const SizedBox(height: 2),
            Text('${date.day}',
                style: GoogleFonts.bebasNeue(
                    fontSize: 20, color: active ? Colors.white : _kInk)),
          ],
        ),
      ),
    );
  }
}

class _AddDayChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddDayChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ADD',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _kMute,
                    letterSpacing: 0.6)),
            const SizedBox(height: 2),
            Text('+',
                style: GoogleFonts.bebasNeue(fontSize: 20, color: _kMute)),
          ],
        ),
      ),
    );
  }
}

const _weekdayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// The active day's panel: title + stop count + Duplicate/Delete (icons —
/// replaces the old collapsible card's text links now that every day isn't
/// independently expandable) above the summary strip + slot sections.
class _DayPanel extends StatelessWidget {
  final Trip trip;
  final int day;
  final int dayCount;
  final Map<String, Gem> gemsById;
  final List<TripBooking> bookings;
  final List<TripStop> allStops;
  const _DayPanel({
    required this.trip,
    required this.day,
    required this.dayCount,
    required this.gemsById,
    required this.bookings,
    required this.allStops,
  });

  @override
  Widget build(BuildContext context) {
    final stops = context.watch<TripProvider>().stopsForDay(trip.id, day);
    final date = trip.startDate.add(Duration(days: day - 1));
    final canDelete = dayCount > 1;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Day $day — ${_dateLabel(date)}',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 20, color: _kInk)),
                      Text(
                          stops.isEmpty
                              ? 'NO ACTIVITIES'
                              : '${stops.length} ${stops.length == 1 ? 'ACTIVITY' : 'ACTIVITIES'}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: _kMute, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Duplicate day',
                  onPressed: () =>
                      context.read<TripProvider>().duplicateDay(trip.id, day),
                  icon:
                      const Icon(Icons.copy_outlined, size: 18, color: _kMute),
                  splashRadius: 18,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  tooltip: 'Delete day',
                  onPressed: canDelete ? () => _confirmDelete(context) : null,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: canDelete ? _kCritical : _kBorder),
                  splashRadius: 18,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _DayBody(
                trip: trip,
                day: day,
                stops: stops,
                gemsById: gemsById,
                bookings: bookings,
                allStops: allStops),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete Day $day?',
            style: GoogleFonts.bebasNeue(fontSize: 20, color: _kInk)),
        content: Text(
            'This removes all of this day\'s activities and shifts later days back by one.',
            style: GoogleFonts.fredoka(color: _kMute)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<TripProvider>().deleteDay(trip.id, day);
            },
            child: const Text('Delete', style: TextStyle(color: _kCritical)),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime d) => '${_months[d.month - 1]} ${d.day}';
}

/// Formats [DayRollup.plannedMinutes] as 'Xh Ym' ('Ym' under an hour, '0m'
/// for nothing timed yet).
String _fmtPlannedMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Planned-time / planned-cost strip, under the day header. Distance is
/// deliberately omitted — see [dayRollup]'s doc comment for why.
class _DaySummaryStrip extends StatelessWidget {
  final DayRollup rollup;
  final String symbol;
  const _DaySummaryStrip({required this.rollup, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 13, color: _kMute),
          const SizedBox(width: 4),
          Text(_fmtPlannedMinutes(rollup.plannedMinutes),
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _kMute)),
          const SizedBox(width: 12),
          const Icon(Icons.payments_outlined, size: 13, color: _kMute),
          const SizedBox(width: 4),
          Text('$symbol${Trip.formatVnd(rollup.plannedCostVnd, short: true)}',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _kMute)),
          if (rollup.tbdCount > 0) ...[
            const SizedBox(width: 4),
            Text('(+${rollup.tbdCount} TBD)',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _kWarn)),
          ],
        ],
      ),
    );
  }
}

/// Slot label/icon — shared by [_SlotSection]'s header and the edit sheet's
/// slot picker. Same icon set as Trip Builder's own `_slotMeta`
/// (itinerary_canvas.dart), so the two surfaces read as one visual system.
String _slotLabel(String slot) => switch (slot) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      _ => slot,
    };

IconData _slotIcon(String slot) => switch (slot) {
      'morning' => Icons.wb_twilight,
      'afternoon' => Icons.wb_sunny_outlined,
      'evening' => Icons.nightlight_round,
      _ => Icons.schedule,
    };

/// A day's body: the planned-time/cost summary strip, its three slot
/// sections, then "+ Add activity".
class _DayBody extends StatelessWidget {
  final Trip trip;
  final int day;
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  final List<TripBooking> bookings;
  final List<TripStop> allStops;
  const _DayBody({
    required this.trip,
    required this.day,
    required this.stops,
    required this.gemsById,
    required this.bookings,
    required this.allStops,
  });

  @override
  Widget build(BuildContext context) {
    Gem? resolveGem(String id) => gemsById[id];
    final rollup =
        dayRollup(stops: stops, bookings: bookings, resolveGem: resolveGem);
    final symbol = currencyFor(trip.currency).symbol;
    // Same stopId->booking relationship unbookedStopAlerts already uses (see
    // dayRollup's doc comment) — built once here, shared by the rollup above
    // and every _SpotRow's own Booked-chip/cost-fallback check below.
    final bookingByStopId = {
      for (final b in bookings)
        if (b.stopId != null) b.stopId!: b,
    };
    // Which bookings fall on THIS day, and where — derived only, never a
    // TripStop (see the "BOOKINGS ON THE ITINERARY" section doc above).
    final dayBookings = bookingsForDay(bookings, day, trip.startDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in dayBookings.stayBanners) ...[
          _StayBanner(
              booking: b, trip: trip, stops: allStops, gemsById: gemsById),
          const SizedBox(height: 10),
        ],
        if (stops.isNotEmpty) _DaySummaryStrip(rollup: rollup, symbol: symbol),
        for (final slot in const ['morning', 'afternoon', 'evening'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SlotSection(
              tripId: trip.id,
              day: day,
              slot: slot,
              stops: stops.where((s) => s.slot == slot).toList(),
              gemsById: gemsById,
              bookingByStopId: bookingByStopId,
              symbol: symbol,
              bookingChips: [
                for (final c in dayBookings.chips[slot]!)
                  _BookingChipRow(
                      data: c, trip: trip, stops: allStops, gemsById: gemsById),
              ],
            ),
          ),
      ],
    );
  }
}

/// One slot's stops within a day: a header, then either an empty line, a
/// single row, or a reorderable list — always rendered even when empty, so
/// the day's three-part shape reads at a glance (mirrors Trip Builder's
/// TimeSlotBlock, which does the same for the same reason). Drag-reorder is
/// scoped to THIS slot's stops only; moving a stop to a different slot is
/// the edit sheet's job (its slot picker), not cross-section dragging —
/// matches Trip Builder's own standing "cross-slot moves are a follow-up"
/// scope on ItineraryItemCard.
class _SlotSection extends StatelessWidget {
  final String tripId;
  final int day;
  final String slot;
  final List<TripStop> stops; // already filtered to this slot, in sortOrder
  final Map<String, Gem> gemsById;
  final Map<String, TripBooking> bookingByStopId;
  final String symbol;
  // Pre-built booking-derived rows for this slot (see the "BOOKINGS ON THE
  // ITINERARY" section) — already resolved by _DayBody, so this section just
  // renders them; it never computes which bookings belong here.
  final List<Widget> bookingChips;
  const _SlotSection({
    required this.tripId,
    required this.day,
    required this.slot,
    required this.stops,
    required this.gemsById,
    required this.bookingByStopId,
    required this.symbol,
    required this.bookingChips,
  });

  // The transit thread (leg INTO the stop) renders above the stop's own row
  // as one combined draggable unit — ReorderableListView needs every direct
  // child to be a single reorderable item, so the thread can't be a
  // separate list entry of its own; it travels with the stop it leads into.
  Widget _rowFor(TripStop s, {int? dragHandleIndex}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.hasTransit) _TransitThread(stop: s, symbol: symbol),
        _SpotRow(
          stop: s,
          gem: s.isCustom ? null : gemsById[s.gemId],
          booking: bookingByStopId[s.id],
          dragHandleIndex: dragHandleIndex,
          symbol: symbol,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(_slotIcon(slot), size: 14, color: _kMute),
              const SizedBox(width: 6),
              Text(_slotLabel(slot).toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: _kMute,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              const Spacer(),
              GestureDetector(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddStopSheet(
                      tripId: tripId, day: day, initialSlot: slot, light: true),
                ),
                child: Text('+ ADD',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
              ),
            ],
          ),
        ),
        for (final chip in bookingChips) ...[
          Padding(padding: const EdgeInsets.only(bottom: 8), child: chip),
        ],
        if (stops.isEmpty && bookingChips.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('No activities',
                style: GoogleFonts.fredoka(
                    fontSize: 12, color: _kMute, fontStyle: FontStyle.italic)),
          )
        else if (stops.isEmpty)
          const SizedBox.shrink()
        else if (stops.length == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _rowFor(stops.first),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: stops.length,
            itemBuilder: (context, i) {
              final s = stops[i];
              return Padding(
                key: ValueKey(s.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _rowFor(s, dragHandleIndex: i),
              );
            },
            onReorderItem: (oldIndex, newIndex) {
              HapticFeedback.selectionClick();
              final reordered = List<TripStop>.from(stops);
              reordered.insert(newIndex, reordered.removeAt(oldIndex));
              // Scoped to THIS slot's stops — matches Trip Builder's
              // TimeSlotBlock exactly, unlike the old day-flat call this
              // replaced (see the audit note this rewrite was built from).
              context.read<TripProvider>().reorderStopsInSlot(
                tripId: tripId,
                orderedStopIds: [for (final s in reordered) s.id],
              );
            },
          ),
      ],
    );
  }
}

/// Display-only slot → representative clock time, used only when a stop has
/// no real [TripStop.startTime] set (older stops predating that column). Not
/// a claim that the stop actually starts at that minute.
String _displayTimeFor(String slot) => switch (slot) {
      'morning' => '08:30',
      'afternoon' => '12:00',
      'evening' => '18:00',
      _ => '--:--',
    };

IconData _transitIcon(String mode) {
  final m = mode.toLowerCase();
  if (m.contains('walk')) return Icons.directions_walk;
  if (m.contains('taxi') || m.contains('car') || m.contains('grab')) {
    return Icons.local_taxi;
  }
  if (m.contains('bus')) return Icons.directions_bus;
  if (m.contains('train') || m.contains('rail'))
    return Icons.directions_railway;
  if (m.contains('ferry') || m.contains('boat')) return Icons.directions_boat;
  if (m.contains('bike') || m.contains('cycle')) return Icons.directions_bike;
  if (m.contains('flight') || m.contains('plane')) return Icons.flight;
  return Icons.directions;
}

/// The leg INTO [stop] — how you get from the previous stop to this one
/// (matches the migration's own "transit-IN fields" semantics). Rendered as
/// a thread — icon + text directly on the day-card's own background — not a
/// card of its own, so it reads as connective tissue between two spot rows
/// rather than a third stop.
class _TransitThread extends StatelessWidget {
  final TripStop stop;
  final String symbol;
  const _TransitThread({required this.stop, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[stop.transitMode!];
    if (stop.transitLine != null) parts.add(stop.transitLine!);
    if (stop.transitDurationMin != null) {
      parts.add('${stop.transitDurationMin} min');
    }
    if (stop.transitCostVnd != null) {
      parts.add('$symbol${Trip.formatVnd(stop.transitCostVnd!, short: true)}');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 0, 6),
      child: Row(
        children: [
          Icon(_transitIcon(stop.transitMode!), size: 13, color: _kMute),
          const SizedBox(width: 8),
          Text(parts.join(' · '),
              style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: _kMute)),
        ],
      ),
    );
  }
}

/// Small uppercase status pill — alpha-tinted background, colored text. Same
/// shape as _TravelerRow's/_BookingCard's inline pills, promoted to a shared
/// widget here since a spot row can show two side by side (TBD + Booked).
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.6)),
    );
  }
}

/// Thumbnail tile: gem photo, category emoji fallback, custom glyph, or an
/// "unavailable" icon for an orphaned stop. Mirrors Trip Builder's own
/// `_Thumb` (itinerary_canvas.dart), re-themed light.
class _SpotThumb extends StatelessWidget {
  final TripStop stop;
  final Gem? gem;
  const _SpotThumb({required this.stop, required this.gem});

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (stop.isCustom) {
      inner = const Icon(Icons.edit_note, size: 18, color: _kMute);
    } else if (gem == null) {
      inner = const Icon(Icons.help_outline, size: 18, color: _kMute);
    } else if (gem!.photoUrl != null && gem!.photoUrl!.isNotEmpty) {
      inner = AppNetworkImage(url: gem!.photoUrl!);
    } else {
      inner =
          Center(child: Text(gem!.emoji, style: const TextStyle(fontSize: 18)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(width: 44, height: 44, color: _kPage, child: inner),
    );
  }
}

/// One placed stop: thumbnail, time, name, a `category · duration · cost`
/// meta line, Cost-TBD/Booked chips, and notes. Three render branches for
/// title/category mirror Trip Builder's ItineraryItemCard: a resolved gem, a
/// custom entry, or an orphaned gem stop (gem deleted from the catalogue,
/// which keeps its price and edit/remove affordances rather than
/// auto-deleting).
class _SpotRow extends StatelessWidget {
  final TripStop stop;
  final Gem? gem;
  final TripBooking? booking;
  final int? dragHandleIndex;
  final String symbol;
  const _SpotRow({
    required this.stop,
    required this.gem,
    required this.booking,
    required this.symbol,
    this.dragHandleIndex,
  });

  @override
  Widget build(BuildContext context) {
    final title = stop.isCustom
        ? (stop.customTitle ?? 'Custom stop')
        : (gem?.gemName ?? 'Gem unavailable');
    final category =
        stop.isCustom ? 'Custom' : (gem?.displayCategory ?? 'Unavailable');
    final timeLabel = stop.startTime ?? _displayTimeFor(stop.slot);
    final duration = stop.isCustom ? null : gem?.estDurationMin;

    // Same cost-resolution order as dayRollup (own price, else a pinned
    // booking's amount, else TBD) — keeps the row's number consistent with
    // what the day-summary strip actually totals.
    final resolvedCost = stop.priceVnd ?? booking?.amountVnd;

    final metaParts = <String>[
      category,
      if (duration != null) '${duration}m',
      if (resolvedCost != null)
        (resolvedCost == 0
            ? 'Free'
            : '$symbol${Trip.formatVnd(resolvedCost, short: true)}'),
    ];

    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dragHandleIndex != null)
            ReorderableDragStartListener(
              index: dragHandleIndex!,
              child: const Padding(
                padding: EdgeInsets.only(right: 6, top: 12),
                child: Icon(Icons.drag_indicator, size: 18, color: _kMute),
              ),
            ),
          _SpotThumb(stop: stop, gem: gem),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(timeLabel,
                    style: GoogleFonts.fredoka(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kMute)),
                const SizedBox(height: 2),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk)),
                const SizedBox(height: 3),
                Text(metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5, color: _kMute, letterSpacing: 0.3)),
                if (resolvedCost == null || booking != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (resolvedCost == null)
                        const _StatusChip(label: 'COST TBD', color: _kWarn),
                      if (booking != null)
                        const _StatusChip(label: 'BOOKED', color: _kGreen),
                    ],
                  ),
                ],
                if ((stop.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(stop.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fredoka(
                          fontSize: 11, color: _kMute, height: 1.3)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ActivityEditSheet(stop: stop),
            ),
            icon: const Icon(Icons.edit_outlined, size: 16, color: _kMute),
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<TripProvider>().removeStop(stop.id);
            },
            icon: const Icon(Icons.close, size: 18, color: _kMute),
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Shared light-palette input decoration — the app's global theme is dark
/// (AppTheme.darkTheme, ThemeMode.dark app-wide), but these sheets render on
/// the profile's light surface, so TextFields need explicit light styling
/// rather than inheriting the ambient dark defaults.
InputDecoration _lightFieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.fredoka(fontSize: 14, color: _kMute),
      filled: true,
      fillColor: _kCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
    );

/// Inline editor for an existing activity: slot, title (custom stops only —
/// a gem-backed stop's title is catalogue data), start time, notes. The slot
/// picker is new — it's the answer to "how do you move a stop to a
/// different slot" now that drag-reorder is scoped within a slot (see
/// _SlotSection's doc comment).
class _ActivityEditSheet extends StatefulWidget {
  final TripStop stop;
  const _ActivityEditSheet({required this.stop});

  @override
  State<_ActivityEditSheet> createState() => _ActivityEditSheetState();
}

class _ActivityEditSheetState extends State<_ActivityEditSheet> {
  late final _titleCtrl =
      TextEditingController(text: widget.stop.customTitle ?? '');
  late final _notesCtrl = TextEditingController(text: widget.stop.notes ?? '');
  // Blank means TBD (null), matching TripStop.priceVnd's MONEY CONTRACT — a
  // confirmed-free stop shows '0' explicitly, same convention as Trip
  // Builder's PriceEditPill (itinerary_canvas.dart).
  late final _priceCtrl =
      TextEditingController(text: widget.stop.priceVnd?.toString() ?? '');
  String? _time;
  late String _slot = widget.stop.slot;

  @override
  void initState() {
    super.initState();
    _time = widget.stop.startTime;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _parseTime(_time) ?? TimeOfDay.now());
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  void _save() {
    context.read<TripProvider>().updateStopDetails(
          widget.stop.id,
          title: _titleCtrl.text.trim(),
          startTime: _time,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          slot: _slot,
        );
    final digits = _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final price = digits.isEmpty ? null : int.tryParse(digits);
    if (price != widget.stop.priceVnd) {
      context.read<TripProvider>().updateStopPrice(widget.stop.id, price);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = currencyFor(context.select<TripProvider, String?>(
        (p) => p.tripById(widget.stop.tripId)?.currency)).symbol;
    // DraggableScrollableSheet (not a MainAxisSize.min Container) — a short
    // sheet leaves the default showModalBottomSheet scrim (translucent
    // black54, not opaque) exposed near the screen bottom, and the bottom nav
    // bar shows through dimmed rather than hidden. A fixed viewport fraction
    // reliably occludes it instead, matching EditTripSheet/showTripSwitcherSheet.
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: _kBorder, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit activity',
                        style:
                            GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
                    const SizedBox(height: 16),
                    if (widget.stop.isCustom) ...[
                      TextField(
                        controller: _titleCtrl,
                        style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                        decoration: _lightFieldDecoration('Title'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in const [
                          'morning',
                          'afternoon',
                          'evening'
                        ])
                          _TypeChip(
                            label: _slotLabel(s),
                            selected: _slot == s,
                            onTap: () => setState(() => _slot = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder)),
                        child: Row(children: [
                          const Icon(Icons.access_time,
                              size: 18, color: _kMute),
                          const SizedBox(width: 10),
                          Text(_time ?? 'Set a time',
                              style: GoogleFonts.fredoka(
                                  fontSize: 14,
                                  color: _time == null ? _kMute : _kInk)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration(
                              'Price — blank for TBD, 0 for free')
                          .copyWith(prefixText: '$symbol '),
                    ),
                    if (_priceCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Leave blank if you don\'t know the cost yet.',
                          style:
                              GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Notes (optional)'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Save',
                          style: GoogleFonts.fredoka(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// BOOKINGS SEGMENT
// ─────────────────────────────────────────
/// Fixed section order: Stay → Flight → Activity → Transport (the last one
/// is a real 4th BookingType beyond the app's original 3-type mockup — the
/// DB CHECK constraint and model already support it, so it gets its own
/// section rather than being silently folded into Activities).
const _bookingTypeOrder = [
  BookingType.stay,
  BookingType.flight,
  BookingType.activity,
  BookingType.transport,
];

IconData _bookingTypeIcon(BookingType t) => switch (t) {
      BookingType.stay => Icons.hotel_outlined,
      BookingType.flight => Icons.flight_takeoff,
      BookingType.activity => Icons.local_activity_outlined,
      BookingType.transport => Icons.directions_car_outlined,
    };

String _bookingTypeLabel(BookingType t) => switch (t) {
      BookingType.stay => 'Stay',
      BookingType.flight => 'Flight',
      BookingType.activity => 'Activity',
      BookingType.transport => 'Transport',
    };

String _bookingStatusLabel(BookingStatus s) => switch (s) {
      BookingStatus.toBook => 'To book',
      BookingStatus.booked => 'Booked',
      BookingStatus.paid => 'Paid',
    };

/// Same title-resolution ternary as _SpotRow (itinerary rows) — shared here so
/// the stop picker and a booking's "📍 pinned" indicator never disagree with
/// what the Itinerary tab itself calls that stop.
String _stopLabel(TripStop s, Map<String, Gem> gemsById) => s.isCustom
    ? (s.customTitle ?? 'Custom stop')
    : (gemsById[s.gemId]?.gemName ?? 'Gem unavailable');

/// Compact, tinted, non-draggable row for a booking-derived Itinerary entry —
/// visually distinct from a real _SpotRow (no drag handle, no price editor;
/// tap opens the same Edit Booking sheet the Bookings tab uses).
class _BookingChipRow extends StatelessWidget {
  final BookingChipData data;
  final Trip trip;
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  const _BookingChipRow({
    required this.data,
    required this.trip,
    required this.stops,
    required this.gemsById,
  });

  @override
  Widget build(BuildContext context) {
    final b = data.booking;
    final (label, color) = switch (b.status) {
      BookingStatus.toBook => ('TO BOOK', _kWarn),
      BookingStatus.booked => ('BOOKED', _kTeal),
      BookingStatus.paid => ('PAID', _kGreen),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openBookingSheet(context,
          trip: trip, stops: stops, gemsById: gemsById, existing: b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(_bookingTypeIcon(b.bookingType),
                size: 15, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fredoka(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _kInk)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(label,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width banner for a night of a Stay booking that isn't the check-in or
/// check-out day itself — persistent context ("you're still staying here")
/// without repeating a chip in every slot.
class _StayBanner extends StatelessWidget {
  final TripBooking booking;
  final Trip trip;
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  const _StayBanner({
    required this.booking,
    required this.trip,
    required this.stops,
    required this.gemsById,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openBookingSheet(context,
          trip: trip, stops: stops, gemsById: gemsById, existing: booking),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kTeal.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.hotel, size: 16, color: _kTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Staying at ${booking.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fredoka(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _kInk)),
            ),
          ],
        ),
      ),
    );
  }
}

void _openBookingSheet(
  BuildContext context, {
  required Trip trip,
  required List<TripStop> stops,
  required Map<String, Gem> gemsById,
  TripBooking? existing,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BookingFormSheet(
        trip: trip, stops: stops, gemsById: gemsById, existing: existing),
  );
}

class _BookingsSegment extends StatefulWidget {
  final Trip trip;
  const _BookingsSegment({required this.trip});

  @override
  State<_BookingsSegment> createState() => _BookingsSegmentState();
}

class _BookingsSegmentState extends State<_BookingsSegment> {
  @override
  void initState() {
    super.initState();
    // Only the ACTIVE trip's bookings are fetched eagerly (profile_screen.dart
    // _loadStats, for the Overview ALERTS stat) — switching My Trip to a
    // different trip via the trip switcher needs its own fetch. Idempotent/
    // guarded inside the provider, so a warm cache is a no-op.
    context.read<BookingProvider>().fetchForTrip(widget.trip.id);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final bookings = context.watch<BookingProvider>().bookingsFor(trip.id);
    final stops =
        context.watch<TripProvider>().allStopsOrdered(trip.id, trip.nights + 1);
    final gemsById = {
      for (final g in context.watch<GemProvider>().allGems) g.id: g,
    };
    final symbol = currencyFor(trip.currency).symbol;

    if (bookings.isEmpty) {
      return _EmptyState(
        icon: Icons.confirmation_number_outlined,
        title: 'No bookings yet',
        subtitle: 'Flights, stays, and tours you add will show up here.',
        cta: '+ Add booking',
        onTap: () => _openBookingSheet(context,
            trip: trip, stops: stops, gemsById: gemsById),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in _bookingTypeOrder)
          if (bookings.any((b) => b.bookingType == type)) ...[
            _CardHeader(
                icon: _bookingTypeIcon(type),
                label: _bookingTypeLabel(type).toUpperCase(),
                color: AppTheme.primary),
            const SizedBox(height: 10),
            for (final b in bookings.where((b) => b.bookingType == type)) ...[
              _BookingCard(
                  booking: b,
                  trip: trip,
                  symbol: symbol,
                  stops: stops,
                  gemsById: gemsById),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
        GestureDetector(
          onTap: () => _openBookingSheet(context,
              trip: trip, stops: stops, gemsById: gemsById),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('+ Add Booking',
                style: GoogleFonts.fredoka(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kMute)),
          ),
        ),
      ],
    );
  }
}

class _BookingCard extends StatefulWidget {
  final TripBooking booking;
  final Trip trip;
  final String symbol;
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  const _BookingCard({
    required this.booking,
    required this.trip,
    required this.symbol,
    required this.stops,
    required this.gemsById,
  });

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _loggingExpense = false;

  String? get _pinnedLabel {
    final stopId = widget.booking.stopId;
    if (stopId == null) return null;
    final stop = widget.stops.where((s) => s.id == stopId).firstOrNull;
    if (stop == null) return null;
    return _stopLabel(stop, widget.gemsById);
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete booking?',
            style: GoogleFonts.bebasNeue(fontSize: 20, color: _kInk)),
        content: Text(
            'This removes "${widget.booking.title}" from this trip\'s bookings.',
            style: GoogleFonts.fredoka(color: _kMute)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<BookingProvider>().remove(widget.booking.id);
            },
            child: const Text('Delete', style: TextStyle(color: _kCritical)),
          ),
        ],
      ),
    );
  }

  // Per the confirmed design: no automatic/hard link between a booking and an
  // expense (Splits is a different concept — a multi-traveler who-owes-who
  // ledger, not "this trip's cost"). This just pre-fills AddExpenseSheet with
  // the booking's own title/amount/category; the user still reviews, picks a
  // payer/split, and hits Save — nothing is created here.
  Future<void> _logAsExpense() async {
    if (_loggingExpense) return;
    setState(() => _loggingExpense = true);
    final splits = context.read<SplitsProvider>();
    final tripSetup = context.read<TripSetupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final trip = widget.trip;
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
          initialTitle: widget.booking.title,
          initialAmount: widget.booking.amountVnd?.toDouble(),
          initialCategory: bookingCategory(widget.booking),
        ),
      );
    } finally {
      if (mounted) setState(() => _loggingExpense = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final (label, color) = switch (booking.status) {
      BookingStatus.toBook => ('TO BOOK', _kWarn),
      BookingStatus.booked => ('BOOKED', _kTeal),
      BookingStatus.paid => ('PAID', _kGreen),
    };
    final pinned = _pinnedLabel;
    final canLogExpense = booking.hasKnownAmount && booking.amountVnd! > 0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.title,
                        style: GoogleFonts.fredoka(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kInk)),
                    const SizedBox(height: 3),
                    Text(_subtitle(booking),
                        style:
                            GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(label,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.6)),
              ),
              IconButton(
                tooltip: 'Edit booking',
                onPressed: () => _openBookingSheet(context,
                    trip: widget.trip,
                    stops: widget.stops,
                    gemsById: widget.gemsById,
                    existing: booking),
                icon: const Icon(Icons.edit_outlined, size: 18, color: _kMute),
                splashRadius: 18,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Delete booking',
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: _kCritical),
                splashRadius: 18,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          if (booking.confirmationRef != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _kBorder))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Confirmation',
                      style: GoogleFonts.fredoka(fontSize: 11, color: _kMute)),
                  Text(booking.confirmationRef!,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kInk,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
          if (booking.hasKnownAmount || pinned != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (booking.hasKnownAmount)
                  Text(
                    booking.amountVnd == 0
                        ? 'Free'
                        : '${widget.symbol}${Trip.formatVnd(booking.amountVnd!, short: true)}',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kInk),
                  ),
                if (pinned != null) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.location_on, size: 13, color: _kTeal),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text('Pinned · $pinned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            GoogleFonts.fredoka(fontSize: 11, color: _kTeal)),
                  ),
                ],
                const Spacer(),
                if (canLogExpense)
                  GestureDetector(
                    onTap: _loggingExpense ? null : _logAsExpense,
                    child: _loggingExpense
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary),
                          )
                        : Text('Log expense',
                            style: GoogleFonts.fredoka(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(TripBooking booking) {
    final parts = <String>[];
    if (booking.provider != null) parts.add(booking.provider!);
    if (booking.startAt != null) {
      parts.add(
          '${_months[booking.startAt!.month - 1]} ${booking.startAt!.day}');
    }
    return parts.join(' · ');
  }
}

/// Type-varying copy for the start/end date pickers — same underlying
/// [TripBooking.startAt]/[endAt] fields for every type, just relabeled so the
/// form reads naturally per booking kind.
({String start, String end}) _bookingDateLabels(BookingType t) => switch (t) {
      BookingType.stay => (start: 'Check-in', end: 'Check-out (optional)'),
      BookingType.flight => (start: 'Departure', end: 'Arrival (optional)'),
      BookingType.activity => (start: 'Date & time', end: 'Ends (optional)'),
      BookingType.transport => (start: 'Departure', end: 'Arrival (optional)'),
    };

String _bookingProviderHint(BookingType t) => switch (t) {
      BookingType.stay => 'e.g. Hanoi Hilton',
      BookingType.flight => 'e.g. Vietnam Airlines',
      BookingType.activity => 'e.g. Local Tour Co.',
      BookingType.transport => 'e.g. Grab, Vietnam Railways',
    };

/// Add/Edit Booking — one sheet for both, switching on [existing]. Mirrors
/// _AddDocumentSheet's shape (type chips → fields → Save), the closest
/// existing "typed child record" form in this file.
class _BookingFormSheet extends StatefulWidget {
  final Trip trip;
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  final TripBooking? existing;
  const _BookingFormSheet({
    required this.trip,
    required this.stops,
    required this.gemsById,
    this.existing,
  });

  @override
  State<_BookingFormSheet> createState() => _BookingFormSheetState();
}

class _BookingFormSheetState extends State<_BookingFormSheet> {
  late final _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _providerCtrl =
      TextEditingController(text: widget.existing?.provider ?? '');
  late final _confirmationCtrl =
      TextEditingController(text: widget.existing?.confirmationRef ?? '');
  late final _amountCtrl =
      TextEditingController(text: widget.existing?.amountVnd?.toString() ?? '');
  late BookingType _type = widget.existing?.bookingType ?? BookingType.stay;
  late BookingStatus _status = widget.existing?.status ?? BookingStatus.toBook;
  DateTime? _startAt;
  DateTime? _endAt;
  String? _stopId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _startAt = widget.existing?.startAt;
    _endAt = widget.existing?.endAt;
    _stopId = widget.existing?.stopId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _providerCtrl.dispose();
    _confirmationCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial != null
          ? TimeOfDay.fromDateTime(initial)
          : const TimeOfDay(hour: 12, minute: 0),
    );
    if (time == null) return DateTime(date.year, date.month, date.day);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_startAt);
    if (picked != null) setState(() => _startAt = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_endAt);
    if (picked != null) setState(() => _endAt = picked);
  }

  // '' (from the sheet's "None" row) means "clear the pin"; null means the
  // sheet was dismissed without a choice — those are NOT the same thing.
  Future<void> _pickStop() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StopPickerSheet(
          stops: widget.stops, gemsById: widget.gemsById, selectedId: _stopId),
    );
    if (picked != null)
      setState(() => _stopId = picked.isEmpty ? null : picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final digits = _amountCtrl.text.trim();
    final amount = digits.isEmpty ? null : int.tryParse(digits);
    final providerText = _providerCtrl.text.trim();
    final confirmationText = _confirmationCtrl.text.trim();

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_isEdit) {
        await context.read<BookingProvider>().update(
              widget.existing!.id,
              title: title,
              bookingType: _type,
              status: _status,
              stopId: _stopId,
              confirmationRef:
                  confirmationText.isEmpty ? null : confirmationText,
              provider: providerText.isEmpty ? null : providerText,
              startAt: _startAt,
              endAt: _endAt,
              amountVnd: amount,
            );
      } else {
        await context.read<BookingProvider>().add(
              tripId: widget.trip.id,
              stopId: _stopId,
              bookingType: _type,
              title: title,
              confirmationRef:
                  confirmationText.isEmpty ? null : confirmationText,
              provider: providerText.isEmpty ? null : providerText,
              startAt: _startAt,
              endAt: _endAt,
              amountVnd: amount,
              status: _status,
              createdBy: context.read<AuthProvider>().user?.id,
            );
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Could not save booking: $e')));
    }
  }

  String _fmtPicked(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year} · ${TimeOfDay.fromDateTime(d).format(context)}';

  @override
  Widget build(BuildContext context) {
    final labels = _bookingDateLabels(_type);
    final symbol = currencyFor(widget.trip.currency).symbol;
    final pinnedStop = widget.stops.where((s) => s.id == _stopId).firstOrNull;
    final stopLabel = pinnedStop == null
        ? 'Not pinned to a stop'
        : _stopLabel(pinnedStop, widget.gemsById);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: _kBorder, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_isEdit ? 'Edit booking' : 'Add booking',
                        style:
                            GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in BookingType.values)
                          _TypeChip(
                            label: _bookingTypeLabel(t),
                            selected: t == _type,
                            onTap: () => setState(() => _type = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _providerCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration:
                          _lightFieldDecoration(_bookingProviderHint(_type)),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder)),
                        child: Row(children: [
                          const Icon(Icons.event_outlined,
                              size: 18, color: _kMute),
                          const SizedBox(width: 10),
                          Text(
                              _startAt == null
                                  ? labels.start
                                  : _fmtPicked(_startAt!),
                              style: GoogleFonts.fredoka(
                                  fontSize: 14,
                                  color: _startAt == null ? _kMute : _kInk)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickEnd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder)),
                        child: Row(children: [
                          const Icon(Icons.event_outlined,
                              size: 18, color: _kMute),
                          const SizedBox(width: 10),
                          Text(
                              _endAt == null ? labels.end : _fmtPicked(_endAt!),
                              style: GoogleFonts.fredoka(
                                  fontSize: 14,
                                  color: _endAt == null ? _kMute : _kInk)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmationCtrl,
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration(
                          'Confirmation number (optional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.fredoka(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Blank = TBD, 0 = free')
                          .copyWith(prefixText: '$symbol '),
                    ),
                    const SizedBox(height: 14),
                    Text('Status',
                        style: GoogleFonts.fredoka(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _kMute)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in BookingStatus.values)
                          _TypeChip(
                            label: _bookingStatusLabel(s),
                            selected: s == _status,
                            onTap: () => setState(() => _status = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Itinerary stop',
                        style: GoogleFonts.fredoka(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _kMute)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickStop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder)),
                        child: Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 18,
                              color: _stopId == null ? _kMute : _kTeal),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(stopLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.fredoka(
                                    fontSize: 14,
                                    color: _stopId == null ? _kMute : _kInk)),
                          ),
                          const Icon(Icons.keyboard_arrow_down,
                              size: 20, color: _kMute),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Save',
                              style: GoogleFonts.fredoka(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick-one-of-this-trip's-stops sheet for the booking form's "pinned"
/// indicator source. Mirrors the currency picker sheet's shape
/// (step_one_init.dart's _CurrencySheet) — rounded-top list, checkmark on the
/// selected row — adapted for a "None" first row instead of a fixed list.
class _StopPickerSheet extends StatelessWidget {
  final List<TripStop> stops;
  final Map<String, Gem> gemsById;
  final String? selectedId;
  const _StopPickerSheet(
      {required this.stops, required this.gemsById, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 60),
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: _kBorder, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(children: [
                Text('Pin to a stop',
                    style: TextStyle(
                        color: _kInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _StopPickerRow(
                    label: 'Not pinned to a stop',
                    selected: selectedId == null,
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  if (stops.isNotEmpty)
                    const Divider(height: 1, color: _kBorder),
                  for (final s in stops)
                    _StopPickerRow(
                      label: '${_stopLabel(s, gemsById)} · Day ${s.day}',
                      selected: s.id == selectedId,
                      onTap: () => Navigator.of(context).pop(s.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StopPickerRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StopPickerRow(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _kInk,
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400)),
            ),
            if (selected)
              const Icon(Icons.check, size: 20, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// DASHBOARD SEGMENT (was Budget) — Overall, Planned vs. actual, Expenses,
// Settle up. "Actual" spend is driven by split_expenses only (confirmed
// decision) — trip_stops.priceVnd is a separate, un-summed source; showing
// both would risk double-counting a cost logged in Trip Builder AND as an
// expense. Trip members for splits/settle-up come from TripSetupProvider's
// trip_collaborators-backed travelers, not split_group_members — there's no
// established "this trip's split group" concept (SplitGroup carries no
// tripId; only individual SplitExpense rows do).
// ─────────────────────────────────────────
class _DashboardSegment extends StatefulWidget {
  final Trip trip;
  const _DashboardSegment({required this.trip});

  @override
  State<_DashboardSegment> createState() => _DashboardSegmentState();
}

class _DashboardSegmentState extends State<_DashboardSegment> {
  final Set<String> _expandedExpenseIds = {};
  bool _openingExpenseSheet = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DashboardSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.id != widget.trip.id) _load();
  }

  void _load() {
    context.read<SplitsProvider>().loadTripDashboard(widget.trip.id);
    context
        .read<TripSetupProvider>()
        .loadSetup(widget.trip.id, ownerId: widget.trip.ownerId);
  }

  /// The hero card's "+ Expense" shortcut moved here — this is the one place
  /// on My Trip that already lists expenses but previously had no way to add
  /// one directly. Same logic _TripCard used (overview_tab.dart): resolve
  /// this trip's shadow split group (auto-provisioning on first use) and its
  /// traveler list, then open the shared AddExpenseSheet pre-scoped to this
  /// trip — no group/trip picker.
  Future<void> _openAddExpense() async {
    if (_openingExpenseSheet) return;
    setState(() => _openingExpenseSheet = true);

    final splits = context.read<SplitsProvider>();
    final tripSetup = context.read<TripSetupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final trip = widget.trip;

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
    final trip = widget.trip;
    final splits = context.watch<SplitsProvider>();
    final travelers = context.watch<TripSetupProvider>().travelersFor(trip.id);
    final travelerById = {for (final t in travelers) t.userId: t};
    final memberIds = travelers.map((t) => t.userId).toList();

    // is_settlement rows are balancing payments, not real spend or line
    // items to browse — excluded from every card below.
    final expenses =
        splits.expensesForTrip(trip.id).where((e) => !e.isSettlement).toList();
    final shares = splits.sharesForTrip(trip.id);
    final settlements = splits.settlementsForTrip(trip.id);

    final spentVnd = expenses.fold<double>(0, (s, e) => s + e.amount).round();
    final actual = actualByCategory(expenses);
    final planned = context.watch<TripProvider>().plannedByCategory(trip.id);
    final balances = settleUpBalances(
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      memberUserIds: memberIds,
    );
    final symbol = currencyFor(trip.currency).symbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardHeader(
            icon: Icons.pie_chart_outline,
            label: 'OVERALL',
            color: AppTheme.primary),
        const SizedBox(height: 10),
        _OverallCard(
            spentVnd: spentVnd, budgetVnd: trip.budgetVnd, symbol: symbol),
        const SizedBox(height: 16),
        const _CardHeader(
            icon: Icons.bar_chart_outlined,
            label: 'PLANNED VS. ACTUAL',
            color: _kTeal),
        const SizedBox(height: 10),
        _PlannedVsActualCard(planned: planned, actual: actual, symbol: symbol),
        const SizedBox(height: 16),
        const _CardHeader(
            icon: Icons.receipt_long_outlined,
            label: 'EXPENSES',
            color: AppTheme.primary),
        const SizedBox(height: 10),
        _ExpensesCard(
          expenses: expenses,
          travelerById: travelerById,
          memberIds: memberIds,
          expandedIds: _expandedExpenseIds,
          onToggleExpand: (id) => setState(() {
            if (!_expandedExpenseIds.add(id)) _expandedExpenseIds.remove(id);
          }),
          sharesForExpense: (expenseId) =>
              shares.where((s) => s.expenseId == expenseId).toList(),
          symbol: symbol,
        ),
        const SizedBox(height: 10),
        // Same "+ Add X" convention as _TravelersCard's "+ Add Traveler" —
        // full-width bordered button, not a header-trailing icon, so it
        // reads consistently across every card on this segment/tab.
        GestureDetector(
          onTap: _openingExpenseSheet ? null : _openAddExpense,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: _openingExpenseSheet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kMute),
                  )
                : Text('+ Add Expense',
                    style: GoogleFonts.fredoka(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kMute)),
          ),
        ),
        const SizedBox(height: 16),
        const _CardHeader(
            icon: Icons.swap_horiz, label: 'SETTLE UP', color: _kGreen),
        const SizedBox(height: 10),
        _SettleUpCard(
            balances: balances, travelerById: travelerById, symbol: symbol),
      ],
    );
  }
}

/// Label + spent/budget figure + a flat orange progress bar (no green/amber/
/// red state — that's the category rows' job below; this card always reads
/// as "here's the one big number", per the prototype's own spec).
class _OverallCard extends StatelessWidget {
  final int spentVnd;
  final int budgetVnd;
  final String symbol;
  const _OverallCard(
      {required this.spentVnd, required this.budgetVnd, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final fill = budgetVnd > 0 ? (spentVnd / budgetVnd).clamp(0.0, 1.0) : 0.0;
    final pct = budgetVnd > 0 ? (spentVnd / budgetVnd * 100).round() : 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$symbol${Trip.formatVnd(spentVnd, short: true)}',
                  style: GoogleFonts.bebasNeue(fontSize: 26, color: _kInk)),
              const SizedBox(width: 6),
              Text('/ $symbol${Trip.formatVnd(budgetVnd, short: true)}',
                  style: GoogleFonts.fredoka(fontSize: 13, color: _kMute)),
              const Spacer(),
              Text('$pct% SPENT',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: _kMute,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(children: [
              Container(height: 8, color: _kBorder),
              FractionallySizedBox(
                  widthFactor: fill,
                  child: Container(height: 8, color: AppTheme.primary)),
            ]),
          ),
        ],
      ),
    );
  }
}

const _dashboardCategoryLabels = {
  'stay': 'Stay',
  'food': 'Food',
  'transit': 'Transport',
  'activity': 'Activities',
  'misc': 'Misc',
};

/// One row per tracked category (stay/food/transit/activity/misc — a
/// Dashboard-local list, deliberately NOT written into the shared
/// TripProvider.budgetCategories constant, which Trip Summary/Trip Builder
/// also read; adding 'misc' there would put an always-zero row on those
/// other screens too).
class _PlannedVsActualCard extends StatelessWidget {
  final Map<String, int> planned;
  final Map<String, double> actual;
  final String symbol;
  const _PlannedVsActualCard(
      {required this.planned, required this.actual, required this.symbol});

  @override
  Widget build(BuildContext context) {
    const keys = ['stay', 'food', 'transit', 'activity', 'misc'];
    return _Card(
      child: Column(
        children: [
          for (final (i, key) in keys.indexed) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: _kBorder),
              ),
            _CategoryBudgetRow(
              label: _dashboardCategoryLabels[key]!,
              plannedVnd: planned[key] ?? 0,
              actualVnd: (actual[key] ?? 0).round(),
              symbol: symbol,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  final String label;
  final int plannedVnd;
  final int actualVnd;
  final String symbol;
  const _CategoryBudgetRow(
      {required this.label,
      required this.plannedVnd,
      required this.actualVnd,
      required this.symbol});

  @override
  Widget build(BuildContext context) {
    // Reuses BudgetStatus's pct/over/near thresholds (the house definition of
    // "close to budget"), mapped onto this file's own light-palette accents
    // rather than AppTheme.warn/danger — consistent with every other status
    // pill built in this file tonight (Travelers/Documents/Packing).
    final status = BudgetStatus.of(spent: actualVnd, budgetVnd: plannedVnd);
    final color = status.over ? _kCritical : (status.near ? _kWarn : _kGreen);
    final fill = plannedVnd > 0
        ? (actualVnd / plannedVnd).clamp(0.0, 1.0)
        : (actualVnd > 0 ? 1.0 : 0.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: GoogleFonts.fredoka(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _kInk)),
            if (status.over) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _kCritical.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5)),
                child: Text('OVER',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: _kCritical,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            const Spacer(),
            Text(
                '$symbol${Trip.formatVnd(actualVnd, short: true)} / $symbol${Trip.formatVnd(plannedVnd, short: true)}',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _kMute)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            Container(height: 6, color: _kBorder),
            FractionallySizedBox(
                widthFactor: fill, child: Container(height: 6, color: color)),
          ]),
        ),
      ],
    );
  }
}

/// "Mon DD" — reuses the shared _months list (profile_palette.dart).
String _fmtShortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

class _ExpensesCard extends StatelessWidget {
  final List<SplitExpense> expenses;
  final Map<String, TripTraveler> travelerById;
  final List<String> memberIds;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleExpand;
  final List<SplitExpenseShare> Function(String expenseId) sharesForExpense;
  final String symbol;
  const _ExpensesCard({
    required this.expenses,
    required this.travelerById,
    required this.memberIds,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.sharesForExpense,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No expenses logged',
        subtitle: 'Expenses you log against this trip will show up here.',
      );
    }
    return Column(
      children: [
        for (final e in expenses) ...[
          _ExpenseRow(
            expense: e,
            payer: e.paidBy != null ? travelerById[e.paidBy!] : null,
            expanded: expandedIds.contains(e.id),
            onToggle: () => onToggleExpand(e.id),
            shares: sharesForExpense(e.id),
            memberIds: memberIds,
            travelerById: travelerById,
            symbol: symbol,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final SplitExpense expense;
  final TripTraveler? payer;
  final bool expanded;
  final VoidCallback onToggle;
  final List<SplitExpenseShare> shares;
  final List<String> memberIds;
  final Map<String, TripTraveler> travelerById;
  final String symbol;
  const _ExpenseRow({
    required this.expense,
    required this.payer,
    required this.expanded,
    required this.onToggle,
    required this.shares,
    required this.memberIds,
    required this.travelerById,
    required this.symbol,
  });

  String get _metaLine {
    final parts = <String>[];
    final cat = expense.category;
    if (cat != null && cat.isNotEmpty) {
      parts.add(cat[0].toUpperCase() + cat.substring(1));
    }
    if (payer != null) parts.add(payer!.displayName);
    if (expense.expenseDate != null)
      parts.add(_fmtShortDate(expense.expenseDate!));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(expense.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fredoka(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _kInk)),
                      const SizedBox(height: 3),
                      Text(_metaLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5, color: _kMute)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                    '$symbol${Trip.formatVnd(expense.amount.round(), short: true)}',
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk)),
                const SizedBox(width: 4),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: _kMute),
              ],
            ),
          ),
          if (expanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: _kBorder),
            ),
            _SplitDetails(
              expense: expense,
              shares: shares,
              memberIds: memberIds,
              travelerById: travelerById,
              payerId: payer?.userId,
              symbol: symbol,
            ),
          ],
        ],
      ),
    );
  }
}

/// Real per-member shares when [shares] has rows for this expense; otherwise
/// an equal split synthesized across [memberIds] — matches
/// [settleUpBalances]'s own fallback exactly, so the expanded detail here
/// never disagrees with what Settle Up actually computed.
class _SplitDetails extends StatelessWidget {
  final SplitExpense expense;
  final List<SplitExpenseShare> shares;
  final List<String> memberIds;
  final Map<String, TripTraveler> travelerById;
  final String? payerId;
  final String symbol;
  const _SplitDetails({
    required this.expense,
    required this.shares,
    required this.memberIds,
    required this.travelerById,
    required this.payerId,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final hasRealShares = shares.isNotEmpty;
    final equalShare =
        memberIds.isEmpty ? 0.0 : expense.amount / memberIds.length;
    final rows = hasRealShares
        ? shares
        : [
            for (final uid in memberIds)
              SplitExpenseShare(
                  id: '$uid-equal', userId: uid, amount: equalShare),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            hasRealShares
                ? 'CUSTOM SPLIT'
                : 'EQUAL SPLIT · ${memberIds.length} ${memberIds.length == 1 ? 'PERSON' : 'PEOPLE'}',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5,
                color: _kMute,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final s in rows)
          _SplitMemberRow(
            traveler: s.userId != null ? travelerById[s.userId!] : null,
            amountVnd: s.amount.round(),
            isPayer: s.userId != null && s.userId == payerId,
            isSettled: s.isSettled,
            symbol: symbol,
          ),
      ],
    );
  }
}

class _SplitMemberRow extends StatelessWidget {
  final TripTraveler? traveler;
  final int amountVnd;
  final bool isPayer;
  final bool isSettled;
  final String symbol;
  const _SplitMemberRow({
    required this.traveler,
    required this.amountVnd,
    required this.isPayer,
    required this.isSettled,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = isPayer
        ? ('PAID', _kGreen)
        : (isSettled
            ? ('SETTLED', _kGreen)
            : (
                'OWES $symbol${Trip.formatVnd(amountVnd, short: true)}',
                _kWarn
              ));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (traveler != null)
            _TravelerAvatar(traveler: traveler!, size: 24)
          else
            Container(
              width: 24,
              height: 24,
              decoration:
                  const BoxDecoration(color: _kCard, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline, size: 14, color: _kMute),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(traveler?.displayName ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fredoka(fontSize: 12.5, color: _kInk)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Text(label,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.4)),
          ),
        ],
      ),
    );
  }
}

/// Derived from [settleUpBalances] — never manually entered (per the brief).
class _SettleUpCard extends StatelessWidget {
  final List<Balance> balances;
  final Map<String, TripTraveler> travelerById;
  final String symbol;
  const _SettleUpCard(
      {required this.balances,
      required this.travelerById,
      required this.symbol});

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) {
      return const _EmptyState(
        icon: Icons.celebration_outlined,
        title: 'All settled up',
        subtitle: 'Nobody owes anybody for this trip right now.',
      );
    }
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, b) in balances.indexed)
            _SettleUpRow(
              balance: b,
              from: travelerById[b.fromUserId],
              to: travelerById[b.toUserId],
              divider: i > 0,
              symbol: symbol,
            ),
        ],
      ),
    );
  }
}

class _SettleUpRow extends StatelessWidget {
  final Balance balance;
  final TripTraveler? from;
  final TripTraveler? to;
  final bool divider;
  final String symbol;
  const _SettleUpRow(
      {required this.balance,
      required this.from,
      required this.to,
      required this.divider,
      required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border:
              divider ? const Border(top: BorderSide(color: _kBorder)) : null),
      child: Row(
        children: [
          if (from != null) _TravelerAvatar(traveler: from!, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                '${from?.displayName ?? 'Someone'} → ${to?.displayName ?? 'someone'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fredoka(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kInk)),
          ),
          const SizedBox(width: 8),
          if (to != null) _TravelerAvatar(traveler: to!, size: 28),
          const SizedBox(width: 10),
          Text(
              '$symbol${Trip.formatVnd(balance.amountVnd.round(), short: true)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
        ],
      ),
    );
  }
}

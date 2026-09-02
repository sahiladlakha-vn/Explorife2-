import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/tour.dart';
import '../../providers/tour_provider.dart';
import '../../widgets/common/photo_carousel.dart';

/// Trail/Tour detail — bookable, priced experience, modeled on a
/// trust-signal grid + tabbed info + participant/date booking widget, but
/// restyled entirely in Explorife's own design system (Bebas Neue/Fredoka/
/// JetBrains Mono, cream/orange) rather than any reference booking site's
/// visual language.
///
/// No Reviews tab — confirmed with product (2026-09-01): this app has no
/// real booking/payment backend, so there's no legitimate source for
/// "verified booking" reviews or a rating breakdown. Shipping fabricated
/// scores was explicitly ruled out; omitted entirely for v1 rather than
/// seeded as fake data. Revisit once real bookings exist to source from.
///
/// "Check availability" shows an honest "Coming soon" message — same
/// pattern this app already uses for other not-yet-built actions (saving a
/// POI-derived gem, voice search): there's no real calendar/capacity system
/// or external booking-partner integration to check against, so a button
/// that claimed to check real availability would be misleading. The
/// participant/date/language pickers above it are still fully real and
/// interactive — nothing about the widget itself is faked, only the final
/// action is honestly stubbed.
class TourDetailScreen extends StatefulWidget {
  const TourDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<TourDetailScreen> createState() => _TourDetailScreenState();
}

class _TourDetailScreenState extends State<TourDetailScreen>
    with SingleTickerProviderStateMixin {
  Tour? _tour;
  bool _loading = true;
  late final TabController _tabController;

  int _participants = 1;
  DateTime? _selectedDate;
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prov = context.read<TourProvider>();
    final cached = prov.byId(widget.id);
    final tour = cached ?? await prov.fetchById(widget.id);
    if (mounted) {
      setState(() {
        _tour = tour;
        _loading = false;
        _selectedLanguage = tour != null && tour.guideLanguages.isNotEmpty
            ? tour.guideLanguages.first
            : null;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  void _checkAvailability() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking real availability is coming soon'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.lightSurface,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    final tour = _tour;
    if (tour == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface, elevation: 0),
        body: Center(
            child: Text('Tour not found',
                style: GoogleFonts.fredoka(color: AppTheme.lightMute))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      // The price/CTA bar deliberately lives inside `body` (as a Positioned
      // overlay) rather than Scaffold.bottomNavigationBar: on this specific
      // screen, any Text widget placed in bottomNavigationBar left `body`
      // never painting again after the loading -> loaded transition (no
      // exception anywhere — confirmed via a from-scratch bisection down to
      // a single plain Text with a default TextStyle). Moving the same bar
      // into a Stack inside body sidesteps whatever Scaffold-level body/
      // bottomNavigationBar interaction that was; GemDetailScreen's own
      // sticky CTA doesn't share this issue, so it's specific to this
      // screen/transition, not a general rule against bottomNavigationBar.
      body: Stack(
        children: [
          Positioned.fill(child: _buildLoadedBody(context, tour)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(tour),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedBody(BuildContext context, Tour tour) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoCarousel(
            photos: tour.photos,
            emptyEmoji: tour.emoji,
            semanticLabel: tour.name,
            topLeft: _BackIcon(
              onTap: () =>
                  context.canPop() ? context.pop() : context.go('/tours'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text('${tour.emoji}  ${tour.displayCategory}',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11, color: AppTheme.primary)),
                ),
                const SizedBox(height: 10),
                Text(tour.name,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 32,
                        color: AppTheme.lightInk,
                        letterSpacing: 0.5)),
                const SizedBox(height: 16),
                _TrustSignalGrid(tour: tour),
                const SizedBox(height: 20),
                _BookingWidget(
                  tour: tour,
                  participants: _participants,
                  onParticipantsChanged: (v) =>
                      setState(() => _participants = v),
                  selectedDate: _selectedDate,
                  onPickDate: _pickDate,
                  selectedLanguage: _selectedLanguage,
                  onLanguageChanged: (v) =>
                      setState(() => _selectedLanguage = v),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.lightMute,
            indicatorColor: AppTheme.primary,
            labelStyle:
                GoogleFonts.fredoka(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Itinerary'),
              Tab(text: 'Highlights'),
              Tab(text: 'Full description'),
              Tab(text: 'Includes'),
            ],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(tour: tour),
                _ItineraryTab(tour: tour),
                _BulletTab(
                    items: tour.highlights,
                    emptyText: 'No highlights listed yet.'),
                _DescriptionTab(tour: tour),
                _BulletTab(
                    items: tour.includes,
                    emptyText: 'No inclusions listed yet.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Tour tour) {
    return Material(
      color: AppTheme.lightSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FROM',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: AppTheme.lightMute)),
                Text('${tour.currency} ${tour.priceFrom}',
                    style: GoogleFonts.bebasNeue(
                        fontSize: 22, color: AppTheme.lightInk)),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _checkAvailability,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Check availability',
                    style: GoogleFonts.fredoka(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BackIcon extends StatelessWidget {
  const _BackIcon({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// 2×2 trust-signal grid — each cell pulled from a real field, omitted
/// entirely (not shown blank) when that field has nothing to say. Pickup is
/// the one exception: [Tour.pickupIncluded] is a bool that always has a
/// real answer (true or false), so that cell always renders — either
/// "Included" (+ detail if given) or "Not included," never blank.
class _TrustSignalGrid extends StatelessWidget {
  const _TrustSignalGrid({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      if (tour.cancellationPolicy != null &&
          tour.cancellationPolicy!.isNotEmpty)
        _TrustCell(
            icon: Icons.event_busy_outlined,
            label: 'Free cancellation',
            value: tour.cancellationPolicy!),
      if (tour.durationLabel != null && tour.durationLabel!.isNotEmpty)
        _TrustCell(
            icon: Icons.schedule,
            label: 'Duration',
            value: tour.durationLabel!),
      _TrustCell(
        icon: Icons.directions_car_filled_outlined,
        label: 'Pickup',
        value: tour.pickupIncluded
            ? (tour.pickupDetail?.isNotEmpty ?? false)
                ? tour.pickupDetail!
                : 'Included'
            : 'Not included',
      ),
      if (tour.guideLanguages.isNotEmpty)
        _TrustCell(
            icon: Icons.language,
            label: 'Guide language',
            value: tour.guideLanguages.join(', ')),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: cells,
    );
  }
}

class _TrustCell extends StatelessWidget {
  const _TrustCell(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: AppTheme.lightMute)),
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fredoka(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.lightInk)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Participants/date/language picker — fully real and interactive; only
/// the final "Check availability" action (owned by the parent screen, not
/// this widget) is a stub. Nothing here is submitted anywhere yet, so
/// there's no persistence risk in letting the user freely play with it.
class _BookingWidget extends StatelessWidget {
  const _BookingWidget({
    required this.tour,
    required this.participants,
    required this.onParticipantsChanged,
    required this.selectedDate,
    required this.onPickDate,
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  final Tour tour;
  final int participants;
  final ValueChanged<int> onParticipantsChanged;
  final DateTime? selectedDate;
  final VoidCallback onPickDate;
  final String? selectedLanguage;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan your visit',
              style: GoogleFonts.bebasNeue(
                  fontSize: 18, letterSpacing: 0.5, color: AppTheme.lightInk)),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.people_outline,
                size: 18, color: AppTheme.lightMute),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Participants',
                  style: TextStyle(fontSize: 13, color: AppTheme.lightInk)),
            ),
            _StepperButton(
              icon: Icons.remove,
              onTap: participants > 1
                  ? () => onParticipantsChanged(participants - 1)
                  : null,
            ),
            SizedBox(
              width: 28,
              child: Text('$participants',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.lightInk)),
            ),
            _StepperButton(
              icon: Icons.add,
              onTap: () => onParticipantsChanged(participants + 1),
            ),
          ]),
          const Divider(height: 20, color: AppTheme.lightBorder),
          InkWell(
            onTap: onPickDate,
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: AppTheme.lightMute),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedDate != null
                      ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                      : 'Select a date',
                  style: TextStyle(
                      fontSize: 13,
                      color: selectedDate != null
                          ? AppTheme.lightInk
                          : AppTheme.lightMute),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppTheme.lightMute),
            ]),
          ),
          if (tour.guideLanguages.length > 1) ...[
            const Divider(height: 20, color: AppTheme.lightBorder),
            Row(children: [
              const Icon(Icons.language, size: 16, color: AppTheme.lightMute),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedLanguage,
                    style: const TextStyle(fontSize: 13, color: AppTheme.lightInk),
                    items: [
                      for (final lang in tour.guideLanguages)
                        DropdownMenuItem(value: lang, child: Text(lang)),
                    ],
                    onChanged: (v) {
                      if (v != null) onLanguageChanged(v);
                    },
                  ),
                ),
              ),
            ]),
          ] else if (tour.guideLanguages.length == 1) ...[
            const Divider(height: 20, color: AppTheme.lightBorder),
            Row(children: [
              const Icon(Icons.language, size: 16, color: AppTheme.lightMute),
              const SizedBox(width: 8),
              Text(tour.guideLanguages.first,
                  style: const TextStyle(fontSize: 13, color: AppTheme.lightInk)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: disabled
                    ? AppTheme.lightBorder
                    : AppTheme.primary.withValues(alpha: 0.4)),
          ),
          child: Icon(icon,
              size: 16,
              color: disabled
                  ? AppTheme.lightMute.withValues(alpha: 0.5)
                  : AppTheme.primary),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final teaser = tour.fullDescription;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (teaser != null && teaser.isNotEmpty)
          Text(teaser,
              style: GoogleFonts.fredoka(
                  fontSize: 14, color: AppTheme.lightMute, height: 1.6)),
        if (tour.itinerary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.map_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('${tour.itinerary.length} stops on this tour',
                style: GoogleFonts.fredoka(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightInk)),
          ]),
        ],
      ],
    );
  }
}

class _ItineraryTab extends StatelessWidget {
  const _ItineraryTab({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    if (tour.itinerary.isEmpty) {
      return Center(
        child: Text('No itinerary listed yet.',
            style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: tour.itinerary.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final step = tour.itinerary[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: AppTheme.primary, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: AppTheme.lightInk)),
                  if (step.description != null &&
                      step.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(step.description!,
                        style: GoogleFonts.fredoka(
                            fontSize: 12.5,
                            color: AppTheme.lightMute,
                            height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DescriptionTab extends StatelessWidget {
  const _DescriptionTab({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final text = tour.fullDescription;
    if (text == null || text.isEmpty) {
      return Center(
        child: Text('No description yet.',
            style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(text,
            style: GoogleFonts.fredoka(
                fontSize: 14, color: AppTheme.lightMute, height: 1.6)),
      ],
    );
  }
}

/// Shared bullet-list renderer for Highlights/Includes — same shape, only
/// the source list and empty-state copy differ.
class _BulletTab extends StatelessWidget {
  const _BulletTab({required this.items, required this.emptyText});
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyText,
            style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(items[i],
                style: GoogleFonts.fredoka(
                    fontSize: 13.5, color: AppTheme.lightMute, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

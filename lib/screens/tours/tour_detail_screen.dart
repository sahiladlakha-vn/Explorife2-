import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/tour.dart';
import '../../providers/tour_provider.dart';
import '../../widgets/common/photo_carousel.dart';
import '../../widgets/tours/tour_detail_shared.dart';

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
/// participant/date/language pickers are still fully real and interactive —
/// nothing about the widget itself is faked, only the final action is
/// honestly stubbed. Saving a tour is stubbed the same way (no
/// `saved_tours` table exists yet — mirrors GemProvider's own
/// not-yet-persisted save affordance on Home's cards).
// Matches the Home rail's own dark card shell exactly (_IdeaStyleCard in
// home_screen.dart, #111827 + white text at descending alpha) — this screen
// used to be built in the app's light/cream theme, a different design
// language than the tour card a user just tapped to get here. The dark
// palette and every tab/pill/quick-facts widget below now live in
// tour_detail_shared.dart, shared with the Home rail's own mini detail card
// (TourExperienceCard) instead of being duplicated here.
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
    _tabController = TabController(length: 4, vsync: this);
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

  Future<void> _pickLanguage(List<String> languages) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Guide language',
                style: GoogleFonts.bebasNeue(
                    fontSize: 18, color: AppTheme.lightInk)),
            const SizedBox(height: 8),
            for (final lang in languages)
              ListTile(
                title: Text(lang, style: const TextStyle(fontSize: 14)),
                trailing: lang == _selectedLanguage
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, lang),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _selectedLanguage = picked);
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

  void _comingSoonSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving tours is coming soon'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: darkBg,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    final tour = _tour;
    if (tour == null) {
      return Scaffold(
        backgroundColor: darkBg,
        appBar: AppBar(backgroundColor: darkBg, elevation: 0),
        body: Center(
            child: Text('Tour not found',
                style: GoogleFonts.fredoka(color: darkMute))),
      );
    }

    return Scaffold(
      backgroundColor: darkBg,
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
      // Bottom padding clears the sticky footer, which now also carries the
      // pill-style booking controls (date/guests/language) — taller than
      // the old price-only bar, so it needs more clearance.
      padding: const EdgeInsets.only(bottom: 132),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoCarousel(
            photos: tour.photos,
            // Same no-photo placeholder as every tour card on the home
            // screen (AppNetworkImage's ImageFallback) — a per-category
            // emoji here looked like a different, unrelated design for the
            // exact same "this tour has no photos" condition.
            emptyIcon: Icons.terrain_rounded,
            semanticLabel: tour.name,
            showIndexBadge: true,
            topLeft: HeaderIcon(
              icon: Icons.arrow_back,
              label: 'Back',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go('/tours'),
            ),
            topRight: HeaderIcon(
              icon: Icons.favorite_border,
              label: 'Save',
              onTap: _comingSoonSave,
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
                        color: Colors.white,
                        letterSpacing: 0.5)),
                const SizedBox(height: 16),
                QuickFactsRow(tour: tour),
                if (tour.cancellationPolicy != null &&
                    tour.cancellationPolicy!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.event_busy_outlined,
                        size: 14, color: darkMute),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tour.cancellationPolicy!,
                          style: GoogleFonts.fredoka(
                              fontSize: 12, color: darkMute)),
                    ),
                  ]),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppTheme.primary,
            unselectedLabelColor: darkFaint,
            indicatorColor: AppTheme.primary,
            labelStyle:
                GoogleFonts.fredoka(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Itinerary'),
              Tab(text: 'Highlights'),
              Tab(text: 'Includes'),
            ],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(
              controller: _tabController,
              children: [
                OverviewTab(tour: tour),
                ItineraryTab(tour: tour),
                BulletTab(
                    items: tour.highlights,
                    emptyText: 'No highlights listed yet.'),
                IncludesTab(tour: tour),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Tour tour) {
    return Material(
      color: darkBg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact pill controls — the "Plan your visit" card this
              // replaced always rendered as a tall, mostly-empty-looking
              // box even for a one-participant, no-date-picked default
              // state. Pills read as controls at a glance instead.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  DatePill(selectedDate: _selectedDate, onTap: _pickDate),
                  const SizedBox(width: 8),
                  GuestPill(
                    participants: _participants,
                    onChanged: (v) => setState(() => _participants = v),
                  ),
                  if (tour.guideLanguages.length > 1) ...[
                    const SizedBox(width: 8),
                    LanguagePill(
                      language: _selectedLanguage ?? tour.guideLanguages.first,
                      onTap: () => _pickLanguage(tour.guideLanguages),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                // Expanded (not a bare Column + Spacer) so a long price
                // string shrinks/wraps instead of pushing the CTA button
                // off the right edge on narrow widths — that combination
                // overflowed by ~58px on a 432-wide viewport before this.
                Expanded(
                  child: Text('From ${tour.currency} ${tour.priceFrom}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bebasNeue(
                          fontSize: 22, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _checkAvailability,
                    // Solid white pill, dark text — same CTA treatment as
                    // every Home rail card's footer button (_IdeaStyleCard),
                    // not this screen's own separate orange-filled button.
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: darkBg,
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
            ],
          ),
        ),
      ),
    );
  }
}


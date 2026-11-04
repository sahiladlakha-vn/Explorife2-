import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../models/tour.dart';
import '../common/photo_carousel.dart';
import 'tour_detail_shared.dart';

/// Home rail's own full mini tour-detail card — renders the same hero,
/// quick facts, tabs, and booking pills as [TourDetailScreen] directly
/// inline in the "Tours & Experiences" rail, instead of only revealing that
/// content after a tap into the full screen. Requested explicitly: a
/// reference mockup showed every rail card as a complete mini detail view
/// ("this card is available inside the tour card, i want that all card
/// should be appear outside on the hero page"), not a thin summary card
/// gating the real content behind navigation.
///
/// Built on the same shared widgets as TourDetailScreen
/// (tour_detail_shared.dart) so both surfaces stay visually and
/// functionally identical — no second, drifting implementation of the
/// quick-facts row, tabs, or pills.
///
/// Same two honest omissions as TourDetailScreen, for the same reasons
/// documented on its own doc comment and on [Tour]'s: no star rating (no
/// rating field exists anywhere on Tour) and no "Departs from X" location
/// line (no location field exists on Tour either — [Tour.pickupDetail] is
/// about pickup, not departure point). The reference mockup showed both;
/// reproducing them here would mean fabricating data this app has no real
/// source for.
///
/// Deliberately NOT wrapped in a single card-wide GestureDetector (unlike
/// `_IdeaStyleCard` elsewhere on Home) — only the hero photo and title open
/// the full [TourDetailScreen] (`context.push('/tours/$id')`); the tabs,
/// pills, and footer CTA all handle their own taps locally so a user can
/// switch tabs / pick a date / adjust guests right here without being
/// bounced to another screen for something this card already does. For the
/// same reason the embedded [TabBarView] uses
/// [NeverScrollableScrollPhysics] — this card lives inside the rail's own
/// horizontally-scrolling `ListView`, so a swipeable tab body here would
/// fight that outer drag gesture; tabs still switch instantly by tapping
/// the [TabBar] itself.
class TourExperienceCard extends StatefulWidget {
  const TourExperienceCard({super.key, required this.tour});

  final Tour tour;

  static const double width = 320;

  /// Generous fixed budget, not a tight fit: hero (180) + tag/title/quick
  /// facts block (~160, itself variable since quick-fact values can wrap to
  /// 2 lines) + TabBar (~48) + divider (1) + pill row (~56) + footer (~56)
  /// leaves a healthy remainder for the Expanded tab body — kept generous
  /// so normal font-metric variance across platforms can't overflow a
  /// non-scrolling Column.
  static const double height = 680;

  @override
  State<TourExperienceCard> createState() => _TourExperienceCardState();
}

class _TourExperienceCardState extends State<TourExperienceCard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _participants = 1;
  DateTime? _selectedDate;
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final languages = widget.tour.guideLanguages;
    _selectedLanguage = languages.isNotEmpty ? languages.first : null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openDetail() => context.push('/tours/${widget.tour.id}');

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

  void _comingSoon(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tour = widget.tour;
    return Container(
      width: TourExperienceCard.width,
      height: TourExperienceCard.height,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        // Same dark shell as every other Home rail card
        // (_IdeaStyleCard's own #111827 + faint white border), so this
        // richer card still visually belongs to the same rail family.
        color: darkBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: darkBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: GestureDetector(
                onTap: _openDetail,
                child: PhotoCarousel(
                  photos: tour.photos,
                  // Same no-photo placeholder as every other tour surface
                  // (AppNetworkImage's ImageFallback via TourDetailScreen's
                  // own choice) rather than a different empty-state design
                  // for the same condition.
                  emptyIcon: Icons.terrain_rounded,
                  semanticLabel: tour.name,
                  aspectRatio: TourExperienceCard.width / 180,
                  showIndexBadge: true,
                  topRight: HeaderIcon(
                    icon: Icons.favorite_border,
                    label: 'Save',
                    onTap: () => _comingSoon('Saving tours is coming soon'),
                  ),
                  // No back icon here (unlike TourDetailScreen's hero) —
                  // there's nothing to go "back" from on a rail card; the
                  // top-left slot instead carries the same never-automatic
                  // "TOP PICK" editorial badge every other Home rail tour
                  // card shows (see Tour.isCurated's own doc comment).
                  topLeft: tour.isCurated
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('TOP PICK',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        )
                      : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openDetail,
                    child: Text(tour.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bebasNeue(
                            fontSize: 22,
                            color: Colors.white,
                            letterSpacing: 0.4)),
                  ),
                  const SizedBox(height: 10),
                  QuickFactsRow(tour: tour),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppTheme.primary,
              unselectedLabelColor: darkFaint,
              indicatorColor: AppTheme.primary,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              labelStyle: GoogleFonts.fredoka(
                  fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Itinerary'),
                Tab(text: 'Highlights'),
                Tab(text: 'Includes'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
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
            Container(height: 1, color: darkDivider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SingleChildScrollView(
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
                      language:
                          _selectedLanguage ?? tour.guideLanguages.first,
                      onTap: () => _pickLanguage(tour.guideLanguages),
                    ),
                  ],
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(children: [
                Expanded(
                  child: Text('From ${tour.currency} ${tour.priceFrom}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bebasNeue(
                          fontSize: 20, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => _comingSoon(
                        'Checking real availability is coming soon'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: darkBg,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Check availability',
                        style: GoogleFonts.fredoka(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

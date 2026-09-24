import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../widgets/gems/category_chip_row.dart';
import '../../widgets/state_views.dart';
import '../listings/listings_screen.dart' show GemResultCard;

/// Destination Detail — opened when a city is selected, either from a
/// destination-scoped card in Home's "Explore Ideas" rail
/// (curated_collections.dart) or from ListingsScreen's Destinations search
/// tab. Both entry points resolve real coordinates first and land here the
/// same way. (Formerly also reached from Home's "Where to next?"
/// DestinationBrowserSheet modal, retired in Phase 2 of the unified search
/// funnel in favor of the Explore Ideas rail.)
///
/// City header + "Plan a trip" CTA stay unchanged. The body used to be its
/// own standalone tab row (Explore / Things to do / Transport / Hotels,
/// sourced from Mapbox Tilequery) with no connection to this app's Gem
/// taxonomy — Phase 1 of the unified search funnel replaces that with a
/// single Gems feed scoped to this city, filtered by the exact same
/// [CategoryChipRow] instance ListingsScreen's Gems tab uses (same state
/// model, order, styling — not a fork).
///
/// "Scoped to this city" is a text match against each Gem's `gemLocation`
/// (via [GemProvider.search], the same substring match every other screen's
/// search already uses) — there's no per-gem geo-radius query in this app
/// yet, and adding one is out of scope for reusing existing data.
///
/// **This feed is sheet-synced Gems ONLY — no Tilequery fill-in.** An
/// earlier pass (commit 1b87033, "filter irrelevant Tilequery POIs from
/// Gems feeds") merged in nearby Mapbox places here too, filtered to
/// travel-relevant categories and deduped against curated Gems. That's
/// been superseded, not layered on top of: Tilequery kept surfacing raw,
/// unedited map data as if it were curated content (a place literally
/// named "Cafe", a mausoleum labeled "Memorial" instead of a real name) —
/// categories that aren't this app's enforced taxonomy at all. Rather than
/// keep tuning the relevance filter, this screen now shows only
/// `GemProvider.fetchGems()`'s `source = 'sheet_sync'` rows (same list —
/// and the same Realtime subscription — every other Gems surface reads
/// from). A destination with no nearby curated Gems yet shows the existing
/// [EmptyStateView] ("No gems in X yet." + "Drop the first gem"), not a
/// fallback list of nearby places, even when Mapbox has real results
/// nearby. If sparse-coverage fill-in is ever wanted again, that's a
/// separate, more deliberate feature (a real category allowlist, decided
/// up front) — not this screen quietly reverting to raw Tilequery data.
///
/// Mapbox/Tilequery is untouched everywhere else it's used for a genuinely
/// different purpose — Gem Detail's "Nearby Experiences" rail
/// (gem_detail_screen.dart) is intentionally broader nearby-discovery, not
/// this curated feed, and ListingsScreen/DestinationDetailScreen's own
/// Tilequery usage is unrelated to this screen entirely.
///
/// [_cityQuery] (not the raw [cityName]) is what actually gets matched
/// against `gemLocation` — [cityName] is the full geocoded label callers
/// pass in (e.g. "Hanoi, Vietnam", confirmed via GeocodingService.fullName),
/// while a real `gemLocation` value is typically "<district>, <city>" with
/// no country word at all (e.g. "Tay Ho District, Hanoi"). Matching the
/// FULL label as one substring silently matched nothing for every real
/// Hanoi gem before this fix — confirmed directly:
/// `"tay ho district, hanoi".contains("hanoi, vietnam")` is false. Taking
/// just the leading segment before the first comma recovers "Hanoi", which
/// does match.
class DestinationLandingScreen extends StatefulWidget {
  const DestinationLandingScreen({
    super.key,
    required this.cityName,
    this.lat,
    this.lng,
  });

  final String cityName;
  final double? lat;
  final double? lng;

  @override
  State<DestinationLandingScreen> createState() =>
      _DestinationLandingScreenState();
}

class _DestinationLandingScreenState extends State<DestinationLandingScreen> {
  String _selectedCat = 'all';

  void _planTrip(BuildContext context) {
    final uri = Uri(path: '/trips/new', queryParameters: {
      'location': widget.cityName,
      if (widget.lat != null) 'lat': '${widget.lat}',
      if (widget.lng != null) 'lng': '${widget.lng}',
    });
    context.push(uri.toString());
  }

  void _dropGem(BuildContext context) {
    context.push('/drop-gem', extra: {
      if (widget.lat != null) 'lat': widget.lat,
      if (widget.lng != null) 'lng': widget.lng,
    });
  }

  void _comingSoonSave(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving gems is coming soon')),
    );
  }

  /// See the class doc comment for why this — not the raw [cityName] — is
  /// what actually gets matched against `gemLocation`.
  String get _cityQuery => widget.cityName.split(',').first.trim();

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    final gemMatches = gem.search(query: _cityQuery, category: _selectedCat);
    final hasAny = gemMatches.isNotEmpty;

    // Same constraints.maxWidth-against-LayoutBuilder pattern
    // gem_detail_screen.dart uses (not Breakpoints.isDesktop(context)'s
    // MediaQuery/window-width check) — this screen renders inside
    // AppShell's ShellRoute too, whose side-nav rail already eats into the
    // window width, so a window-width check would flip to desktop layout
    // too early. Wrapping the whole Scaffold (not just body, as
    // gem_detail_screen.dart does) because the bottom bar being replaced is
    // Scaffold.bottomNavigationBar — a sibling of body, not something
    // inside it — so `isDesktop` needs to be in scope before body is even
    // built.
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= Breakpoints.desktop;
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.lightSurface,
          foregroundColor: AppTheme.lightInk,
          elevation: 0,
          title: Text(widget.cityName),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: CategoryChipRow(
              selected: _selectedCat,
              onSelect: (cat) => setState(() => _selectedCat = cat),
            ),
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Gems in ${widget.cityName}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.lightInk)),
              ),
            ),
            if (gem.loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: TrailListSkeleton(),
                ),
              )
            else if (gem.error != null)
              SliverToBoxAdapter(
                child:
                    ErrorStateView(onRetry: gem.refresh, message: gem.error),
              )
            else if (!hasAny)
              SliverToBoxAdapter(
                child: EmptyStateView(
                  text: 'No gems in ${widget.cityName} yet.',
                  icon: Icons.diamond_outlined,
                  actionLabel: 'Drop the first gem',
                  onAction: () => _dropGem(context),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => GemResultCard(
                      gem: gemMatches[i],
                      onSave: () => _comingSoonSave(ctx),
                    ),
                    childCount: gemMatches.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              ),
            // Desktop-only inline replacement for the mobile sticky bar
            // below (see `isDesktop` above) — lives in normal document flow
            // right after whichever content just rendered (grid, empty
            // state, error, or loading skeleton), so it always sits
            // immediately below the last row instead of being pinned to
            // the bottom of a viewport that's taller than the content.
            if (isDesktop)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: _PlanTripCard(
                    cityName: widget.cityName,
                    onPlanTrip: () => _planTrip(context),
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
        // Mobile/narrow only — see `isDesktop` above and _PlanTripCard's
        // doc comment for why desktop gets an inline card instead of this.
        bottomNavigationBar: isDesktop
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _planTrip(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('+ Plan a trip to ${widget.cityName}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
      );
    });
  }
}

/// Desktop-only inline "Plan a trip" CTA — see build()'s `isDesktop` gate
/// on why this exists instead of just hiding the mobile sticky bar outright
/// (unlike gem_detail_screen.dart's Save button, "plan a trip to this city"
/// has no other home anywhere on this screen, so it can't simply be
/// dropped on desktop — it has to move, not disappear). Sized to this
/// screen's own content padding (same 16px horizontal inset as the gems
/// grid above it), not the full viewport width the mobile bar spans.
class _PlanTripCard extends StatelessWidget {
  const _PlanTripCard({required this.cityName, required this.onPlanTrip});

  final String cityName;
  final VoidCallback onPlanTrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.map_outlined,
                color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ready to explore $cityName?',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.lightInk)),
                const SizedBox(height: 4),
                const Text('Turn these gems into a full day-by-day itinerary.',
                    style: TextStyle(fontSize: 13, color: AppTheme.lightMute)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: onPlanTrip,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Plan a trip',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

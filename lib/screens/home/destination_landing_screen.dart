import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/services/poi_category_filter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../widgets/gems/category_chip_row.dart';
import '../../widgets/state_views.dart';
import '../listings/listings_screen.dart' show GemResultCard, PoiResultCard;

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
/// yet, and adding one is out of scope for reusing existing data. Real
/// nearby Mapbox places still merge in via [MapboxTilequeryService] exactly
/// as this screen already fetched them, unified under the same card
/// presentation ([GemResultCard]/[PoiResultCard]) rather than their own
/// separate "Top things to do"/"Top attractions" rails — a presentation
/// merge only; curated Gems and Mapbox POIs remain two distinct data
/// sources, still rendered with their own honest "GEM" vs. plain badge.
/// POIs are also filtered to travel-relevant categories before they ever
/// reach this feed (see [filterTravelRelevantPois]) — Tilequery otherwise
/// returns government offices, parking, and utility infrastructure right
/// alongside actual points of interest. Gems always render before the
/// filtered POI fill-in (see the grid's index math in build()), never
/// interleaved, so a curated place never gets buried next to an
/// auto-pulled one.
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
  final MapboxTilequeryService _tilequery = MapboxTilequeryService();
  String _selectedCat = 'all';
  List<NearbyPoi> _pois = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lat = widget.lat, lng = widget.lng;
    if (lat == null || lng == null) {
      // No resolved coordinates (geocoding failed upstream) — nothing to
      // query nearby; the scoped Gems feed still works off the city name.
      setState(() => _loading = false);
      return;
    }
    final pois =
        await _tilequery.nearby(lat, lng, radiusMeters: 5000, limit: 50);
    // Tilequery returns everything nearby it knows about — government
    // offices, parking, utility infrastructure — not just things a
    // traveler would want to see. This feed presents POIs as if they were
    // gems, so only travel-relevant categories belong here (unlike Add
    // Stop's own Tilequery fetch, which intentionally shows everything).
    //
    // limit: 50 (Tilequery's actual max — confirmed against the live API,
    // it rejects anything higher) rather than the smaller limit this screen
    // used pre-filtering: Tilequery sorts nearest-first and a city center
    // is often dense with the exact office/government buildings this
    // filter drops, so a small raw sample can filter down to almost
    // nothing even when real gems-worthy places exist slightly farther out.
    final relevant = filterTravelRelevantPois(pois);
    if (mounted)
      setState(() {
        _pois = relevant;
        _loading = false;
      });
  }

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

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    final gemMatches = gem.search(query: widget.cityName, category: _selectedCat);
    // Same rule ListingsScreen uses: a specific category narrows to gems
    // only, since Mapbox's POI categories don't map onto this app's fixed
    // 8-category taxonomy — merging them into a category-filtered view
    // would be a false match, not a real one.
    final includeNearby = _selectedCat == 'all';
    final nearby = includeNearby ? _pois : const <NearbyPoi>[];
    final nearbyStillLoading = includeNearby && _loading;
    final hasAny = gemMatches.isNotEmpty || nearby.isNotEmpty;

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
          if (gem.loading || (gemMatches.isEmpty && nearbyStillLoading))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: TrailListSkeleton(),
              ),
            )
          else if (gem.error != null)
            SliverToBoxAdapter(
              child: ErrorStateView(onRetry: gem.refresh, message: gem.error),
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
                  (ctx, i) {
                    if (i < gemMatches.length) {
                      return GemResultCard(
                        gem: gemMatches[i],
                        onSave: () => _comingSoonSave(ctx),
                      );
                    }
                    return PoiResultCard(poi: nearby[i - gemMatches.length]);
                  },
                  childCount: gemMatches.length + nearby.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 230,
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
  }
}

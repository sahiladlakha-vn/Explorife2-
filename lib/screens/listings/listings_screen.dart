import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/state_views.dart';

/// One card in the merged browse/results grid — either a real, app-curated
/// [Gem] or a generic real place from [MapboxTilequeryService]. Kept as a
/// thin either/or wrapper rather than forcing both into one shape, so each
/// renders with its own card ([_GemCard] vs [_PoiCard]) and the "GEM" badge
/// stays an honest, visible distinction rather than a guess from shared
/// fields.
class _BrowseItem {
  final Gem? gem;
  final NearbyPoi? poi;
  const _BrowseItem.gem(Gem g)
      : gem = g,
        poi = null;
  const _BrowseItem.poi(NearbyPoi p)
      : gem = null,
        poi = p;
}

/// Unified gem search/discovery screen — merges what used to be two separate
/// screens (SearchScreen at /search, and this Listings/Discover screen) into
/// one, reached from three entry points: Home's search bar (autofocusSearch:
/// true), Home's "SEE ALL"/hero CTAs, and the bottom nav's compass tab (both
/// autofocusSearch: false). Same widget, same state, just a different
/// starting focus.
///
/// Three states, mutually exclusive, driven by query/category/focus:
///  - Results:     query non-empty OR a category is picked — one filtered
///                 grid (former Screen A's list and this screen's grid are
///                 now the same _GemCard grid presentation).
///  - Suggestions: search field focused, query empty, category = all —
///                 Popular Searches chips (categories are already visible in
///                 the persistent bar above, so no second categories grid).
///  - Browse:      the default landing state (field unfocused, query empty,
///                 category = all) — Featured Gems rail + All Gems grid,
///                 unchanged from what this screen always showed.
///
/// The "All Gems" grid (Browse, and Results when category = 'all') merges in
/// real nearby places from [MapboxTilequeryService] alongside this app's own
/// curated [Gem]s — added because the gems table can be sparse or briefly
/// empty (e.g. right after a data cleanup) and this screen shouldn't go
/// blank just because there's nothing curated yet. Gems render with a "GEM"
/// badge ([_GemCard]); Mapbox places don't ([_PoiCard], no bookmark button
/// either — saving one would mean creating a real gem from it, which isn't
/// wired up). Picking a specific category narrows to gems only: Mapbox's POI
/// categories don't map onto this app's fixed 8-category taxonomy, so
/// merging them into a category-filtered view would be a false match, not a
/// real one.
class ListingsScreen extends StatefulWidget {
  const ListingsScreen(
      {super.key, this.autofocusSearch = false, this.initialCategory});

  /// True when opened from Home's search bar — lands directly in the
  /// Suggestions state instead of the default Browse view.
  final bool autofocusSearch;

  /// Seeds the category filter — used when opened from Home's category
  /// chips (e.g. tapping "Hiking" lands here pre-filtered to hiking gems)
  /// instead of the default unfiltered Browse view. One of [Gem.categories],
  /// or null for no pre-selection.
  final String? initialCategory;

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final MapboxTilequeryService _tilequery = MapboxTilequeryService();

  // Screen-local search/category state. Deliberately NOT in GemProvider:
  // routing either through the provider would also filter the Map and Home,
  // which share that state. This screen stays pure and local, same
  // reasoning both predecessor screens already documented.
  String _query = '';
  late String _selectedCat = widget.initialCategory ?? 'all';

  // Fetched once per screen visit (not re-fetched per keystroke/category
  // tap — see _matchingNearby, which filters this cached list locally
  // instead of re-querying Mapbox). Starts loading so the grid can tell
  // "nothing nearby" apart from "still finding out" — see _ItemGridSliver.
  List<NearbyPoi> _nearby = [];
  bool _nearbyLoading = true;

  // Ho Chi Minh City centre — used only if location permission is denied or
  // resolving it fails, so the nearby-places section still has *something*
  // to query around rather than silently staying empty. Matches this app's
  // Vietnam focus (same fallback city other screens implicitly center on).
  static const double _fallbackLat = 10.7769;
  static const double _fallbackLng = 106.7009;

  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so the Suggestions/Browse split (which reads
    // _focusNode.hasFocus at build time) actually reacts to the field being
    // tapped into or away from.
    _focusNode.addListener(() => setState(() {}));
    _loadNearby();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Same permission-check/request/fallback shape used elsewhere in the app
  // (e.g. ExploreScreen._locateMe, HomeScreen's _NearbyGems) — there's no
  // shared helper for it yet (a known, separately-tracked gap), so this
  // repeats the pattern rather than half-wiring a new one here.
  Future<void> _loadNearby() async {
    double lat = _fallbackLat, lng = _fallbackLng;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // Keep the Ho Chi Minh City fallback — a denied/unavailable location
      // shouldn't leave this section empty, just less personalized.
    }
    final pois =
        await _tilequery.nearby(lat, lng, radiusMeters: 2000, limit: 20);
    if (mounted)
      setState(() {
        _nearby = pois;
        _nearbyLoading = false;
      });
  }

  /// [_nearby], filtered to whatever's currently active — substring match
  /// against [_query] (case-insensitive, matching gemMatchesSearch's own
  /// convention elsewhere), or the full cached list when there's no query.
  /// Never re-hits Mapbox: this is exactly why [_nearby] is fetched once and
  /// cached rather than re-queried per keystroke/category tap.
  List<NearbyPoi> get _matchingNearby {
    if (_query.trim().isEmpty) return _nearby;
    final q = _query.trim().toLowerCase();
    return _nearby.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  void _setQuery(String value) => setState(() => _query = value);

  void _clearQuery() {
    _controller.clear();
    setState(() => _query = '');
  }

  void _applyChip(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
  }

  void _comingSoonSave(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving gems is coming soon')),
    );
  }

  // Real speech-to-text needs the `speech_to_text` plugin plus a microphone-
  // permission flow — a separate product decision, same reasoning as the
  // Explore map screen's identical placeholder. An honest "coming soon" is
  // better than a dead button.
  void _startVoiceSearch(BuildContext context) {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice search is coming soon — type to search for now.'),
        // Matches the Explore map screen's identical placeholder: floating,
        // with a bottom margin that clears BottomNav's floating pill instead
        // of docking flush above it (Flutter's SnackBar default without an
        // explicit behavior is `fixed`, which was the one inconsistency
        // between these two otherwise-identical snackbars).
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    final hasFilter = _query.isNotEmpty || _selectedCat != 'all';
    final showSuggestions = !hasFilter && _focusNode.hasFocus;
    final featured =
        gem.featured; // GLOBAL trending — independent of any filter

    // Merged grid contents: this app's own gems (real filter) plus cached
    // nearby Mapbox places (local substring match only — see _matchingNearby)
    // — but only in the unfiltered 'All' category view; see the class doc
    // comment for why a specific category drops the Mapbox side entirely.
    final gemResults = gem.search(query: _query, category: _selectedCat);
    final includeNearby = _selectedCat == 'all';
    final nearbyMatches = includeNearby ? _matchingNearby : const <NearbyPoi>[];
    final items = <_BrowseItem>[
      for (final g in gemResults) _BrowseItem.gem(g),
      for (final p in nearbyMatches) _BrowseItem.poi(p),
    ];
    final nearbyStillLoading = includeNearby && _nearbyLoading;

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.lightSurface,
            foregroundColor: AppTheme.lightInk,
            floating: true,
            // Explicit filled/fillColor/borders below — the app-wide
            // inputDecorationTheme is `filled` with a DARK surface (see
            // explore_screen.dart's search field for the same fix/comment),
            // which is why this rendered as a stark black bar before. Style
            // matches the Add Stop sheet's search field / the New Trip
            // wizard's location field exactly — one canonical light-input
            // look, reused rather than redefined here.
            title: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocusSearch,
              onChanged: _setQuery,
              style: const TextStyle(color: AppTheme.lightInk, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search gems, places…',
                hintStyle:
                    const TextStyle(color: AppTheme.lightMute, fontSize: 15),
                prefixIcon: const Icon(Icons.search,
                    color: AppTheme.lightMute, size: 20),
                filled: true,
                fillColor: AppTheme.lightCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppTheme.lightMute, size: 20),
                        onPressed: _clearQuery,
                      ),
                    // Same honest "coming soon" mic placeholder the Explore
                    // map screen's search bar already uses — no real
                    // speech-to-text plugin wired up yet on either screen.
                    IconButton(
                      icon: const Icon(Icons.mic_none_rounded,
                          color: AppTheme.lightMute, size: 20),
                      onPressed: () => _startVoiceSearch(context),
                    ),
                  ],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: _CategoryBar(
                selected: _selectedCat,
                onSelect: (cat) => setState(() => _selectedCat = cat),
              ),
            ),
          ),
          if (showSuggestions)
            _SuggestionsSlivers(popular: gem.popularTerms, onChip: _applyChip)
          else if (hasFilter)
            _ResultsSlivers(
              gem: gem,
              items: items,
              nearbyLoading: nearbyStillLoading,
              onSave: _comingSoonSave,
            )
          else
            _BrowseSlivers(
              gem: gem,
              featured: featured,
              items: items,
              nearbyLoading: nearbyStillLoading,
              onSave: _comingSoonSave,
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

/// Suggestions state: just the Popular Searches chips — the category grid
/// Screen A used to show here is gone, since the same categories are already
/// one persistent bar above (_CategoryBar), not worth showing twice.
class _SuggestionsSlivers extends StatelessWidget {
  const _SuggestionsSlivers({required this.popular, required this.onChip});

  final List<String> popular;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Popular Searches',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lightInk)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: popular
                  .map((term) => GestureDetector(
                        onTap: () => onChip(term),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.lightBorder),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.trending_up,
                                  size: 14, color: AppTheme.lightMute),
                              const SizedBox(width: 6),
                              Text(term,
                                  style: const TextStyle(
                                      fontSize: 13, color: AppTheme.lightInk)),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Browse state (default landing view): Featured Gems rail + All Gems grid —
/// unchanged from what this screen always showed before the merge.
class _BrowseSlivers extends StatelessWidget {
  const _BrowseSlivers({
    required this.gem,
    required this.featured,
    required this.items,
    required this.nearbyLoading,
    required this.onSave,
  });

  final GemProvider gem;
  final List<Gem> featured;
  final List<_BrowseItem> items;
  final bool nearbyLoading;
  final void Function(BuildContext context) onSave;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (featured.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Featured Gems',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.lightInk)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: featured.length,
                itemBuilder: (ctx, i) => _FeaturedGemCard(
                  gem: featured[i],
                  isTrending: gem.isTrending(featured[i]),
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('All Gems',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lightInk)),
          ),
        ),
        _ItemGridSliver(
            gem: gem,
            items: items,
            nearbyLoading: nearbyLoading,
            onSave: onSave),
      ],
    );
  }
}

/// Results state: query non-empty and/or a category picked — one filtered
/// grid, the same card presentation Browse's All Gems uses (replaces Screen
/// A's separate flat-list result rows).
class _ResultsSlivers extends StatelessWidget {
  const _ResultsSlivers({
    required this.gem,
    required this.items,
    required this.nearbyLoading,
    required this.onSave,
  });

  final GemProvider gem;
  final List<_BrowseItem> items;
  final bool nearbyLoading;
  final void Function(BuildContext context) onSave;

  @override
  Widget build(BuildContext context) {
    return _ItemGridSliver(
        gem: gem, items: items, nearbyLoading: nearbyLoading, onSave: onSave);
  }
}

/// Loading/error/empty/data states for the 2-column merged grid — shared by
/// both Browse's "All Gems" section and the Results state. [nearbyLoading]
/// distinguishes "still fetching nearby Mapbox places" from "confirmed
/// nothing matches" — without it, a sparse/empty gems table would flash the
/// empty state for the instant before the Mapbox fetch resolves.
class _ItemGridSliver extends StatelessWidget {
  const _ItemGridSliver({
    required this.gem,
    required this.items,
    required this.nearbyLoading,
    required this.onSave,
  });

  final GemProvider gem;
  final List<_BrowseItem> items;
  final bool nearbyLoading;
  final void Function(BuildContext context) onSave;

  @override
  Widget build(BuildContext context) {
    if (gem.loading || (items.isEmpty && nearbyLoading)) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: TrailListSkeleton(),
        ),
      );
    }
    if (gem.error != null) {
      return SliverToBoxAdapter(
        child: ErrorStateView(onRetry: gem.refresh, message: gem.error),
      );
    }
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: EmptyStateView(text: 'No places match that yet.'),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final item = items[i];
            return item.gem != null
                ? _GemCard(gem: item.gem!, onSave: () => onSave(ctx))
                : _PoiCard(poi: item.poi!);
          },
          childCount: items.length,
        ),
        // Max-extent (not fixed-count): column count derives from whatever
        // cross-axis width the sliver is actually given, so this stays 2
        // columns on a phone-width screen (unchanged) and naturally scales up
        // on a wide desktop viewport instead of stretching 2 cards edge to
        // edge — no breakpoint check needed, the delegate does this itself.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 230,
          childAspectRatio: 0.78,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // 'all' first (primary reset), then the gem categories.
    final cats = <String>['all', ...Gem.categories];

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          final cat = cats[i];
          final isAll = cat == 'all';
          final isSelected = selected == cat;
          final icon =
              isAll ? Icons.public : AppConstants.gemCategoryIcons[cat]!;
          final label = isAll ? 'All' : cat[0].toUpperCase() + cat.substring(1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppTheme.lightInk,
              ),
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onSelect(cat),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.lightCard,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.lightInk,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? Colors.transparent : AppTheme.lightBorder,
              ),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }
}

/// Featured carousel card — same visual language as the Home Featured rail
/// (225w, bottom gradient, TRENDING pill), gem-bound and free of rating/price.
class _FeaturedGemCard extends StatelessWidget {
  const _FeaturedGemCard({required this.gem, required this.isTrending});

  final Gem gem;
  final bool isTrending;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: gem.gemName,
      child: GestureDetector(
        onTap: () => context.push('/gems/${gem.id}'),
        child: Container(
          width: 225,
          margin: const EdgeInsets.only(right: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppNetworkImage(url: gem.photoUrl ?? ''),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
                if (isTrending)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('TRENDING',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gem.displayCategory.toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(gem.gemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      if (gem.gemLocation != null &&
                          gem.gemLocation!.isNotEmpty)
                        Text(gem.gemLocation!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GemCard extends StatelessWidget {
  const _GemCard({required this.gem, required this.onSave});

  final Gem gem;
  final VoidCallback onSave;

  /// Difficulty pill colour by level; null hides the pill entirely.
  ({Color color, String label})? get _difficulty {
    final d = gem.difficulty;
    if (d == null || d.trim().isEmpty) return null;
    switch (d.toLowerCase()) {
      case 'easy':
        return (color: const Color(0xFF2ECC71), label: 'EASY');
      case 'moderate':
      case 'mod':
        return (color: const Color(0xFFFFC107), label: 'MODERATE');
      case 'hard':
        return (color: AppTheme.primary, label: 'HARD');
      default:
        return (color: AppTheme.lightMute, label: d.toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _difficulty;
    return Semantics(
      button: true,
      label: gem.gemName,
      child: GestureDetector(
        onTap: () => context.push('/gems/${gem.id}'),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: AppNetworkImage(url: gem.photoUrl ?? ''),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onSave,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bookmark_outline,
                              size: 18, color: AppTheme.lightMute),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // "GEM · " prefix is the visible distinction from
                        // _PoiCard's plain category pill — this is a real,
                        // app-curated spot, not a generic Mapbox place.
                        child: Text('GEM · ${gem.displayCategory}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gem.gemName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.lightInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (gem.gemLocation != null &&
                        gem.gemLocation!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: AppTheme.lightMute),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(gem.gemLocation!,
                                style: const TextStyle(
                                    color: AppTheme.lightMute, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    if (diff != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: diff.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(diff.label,
                            style: TextStyle(
                                color: diff.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                    ],
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

/// A real nearby place from Mapbox Tilequery — same card shape as [_GemCard]
/// so the merged grid reads as one consistent layout, but deliberately
/// simpler: no bookmark (saving one would mean creating a real gem from it,
/// not wired up), no photo (Tilequery doesn't return one, so a plain icon
/// tile substitutes), and a neutral grey category pill instead of the
/// orange "GEM · " one — the visible tell that this isn't app-curated.
class _PoiCard extends StatelessWidget {
  const _PoiCard({required this.poi});

  final NearbyPoi poi;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      color: AppTheme.lightBorder.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      // Maki-based icon (see NearbyPoi.iconForMaki) instead of
                      // a single generic pin — kept grey/neutral, not orange,
                      // to preserve the GEM-vs-generic-POI tell above.
                      child: Icon(NearbyPoi.iconForMaki(poi.maki),
                          size: 32, color: AppTheme.lightMute),
                    ),
                  ),
                ),
                if (poi.category != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.lightMute.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(poi.category!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.lightInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (poi.distanceMeters != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: AppTheme.lightMute),
                      const SizedBox(width: 2),
                      Text('${poi.distanceMeters!.round()}m away',
                          style: const TextStyle(
                              color: AppTheme.lightMute, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

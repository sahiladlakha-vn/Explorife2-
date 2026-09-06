import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/curated_destinations.dart';
import '../../core/services/geocoding_service.dart';
import '../../providers/gem_provider.dart';
import '../../providers/tour_provider.dart';
import '../../models/gem.dart';
import '../../models/tour.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/gems/category_chip_row.dart';
import '../../widgets/state_views.dart';

/// One match in the Destinations tab — a curated city (see
/// curated_destinations.dart) whose name contains the current search query.
/// [photoUrl] is only ever set for a country's "top" cities; its secondary
/// chip-only cities (moreCities) carry no photo, same as
/// curated_destinations.dart's own top/more-cities split.
class _DestinationMatch {
  final String cityName;
  final String countryName;
  final String? photoUrl;
  const _DestinationMatch(
      {required this.cityName, required this.countryName, this.photoUrl});
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
///                 now the same GemResultCard grid presentation). When the query
///                 is non-empty, results also split into a Destinations /
///                 Gems / Tours tab trio (see [_ResultTabBar]) — a query can
///                 match a place name, a gem/venue name, a tour name, or any
///                 combination at once, and each tab surfaces its own
///                 matches independently rather than one search silently
///                 picking a winner.
///  - Suggestions: search field focused, query empty, category = all —
///                 Popular Searches chips (categories are already visible in
///                 the persistent bar above, so no second categories grid).
///  - Browse:      the default landing state (field unfocused, query empty,
///                 category = all) — Featured Gems rail + All Gems grid,
///                 unchanged from what this screen always showed.
///
/// Destinations tab: queries the same curated country/city list
/// (curated_destinations.dart) Home's "Explore Ideas" destination-scoped
/// collection cards use (curated_collections.dart) — no new destination
/// data source for this. Selecting one resolves real coordinates via
/// [GeocodingService] (same geocode-then-navigate pattern every city-tap
/// flow in this app shares) and lands on the same `/destinations/explore`
/// destination detail screen either entry point uses.
///
/// The "All Gems" grid (Browse, and Results) is `source = 'sheet_sync'`
/// [Gem]s only — no Mapbox Tilequery fill-in. This screen used to merge in
/// nearby real-world places once the gems table ran thin, rendered with a
/// plain (non-"GEM") badge to stay honest about the distinction. That's
/// been removed, not just filtered further, for the same reason
/// destination_landing_screen.dart's scoped feed dropped it: Tilequery kept
/// surfacing raw, unedited map data (a place literally named "Cafe", a
/// mausoleum labeled "Memorial") outside this app's enforced taxonomy. A
/// sparse category now shows [EmptyStateView] ("No places match that
/// yet."), not a fallback list of real places, even when Mapbox has
/// results nearby.
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

  // Screen-local search/category state. Deliberately NOT in GemProvider:
  // routing either through the provider would also filter the Map and Home,
  // which share that state. This screen stays pure and local, same
  // reasoning both predecessor screens already documented.
  String _query = '';
  late String _selectedCat = widget.initialCategory ?? 'all';

  // 0 = Destinations, 1 = Gems, 2 = Tours. Only consulted when the query is
  // non-empty (destinations/tours don't apply to a bare category filter).
  // Recomputed on every query change in [_setQuery] so a fresh search always
  // gets a sensible default; a user's manual tap sticks until the next
  // keystroke, unless the tab they're on empties out (handled by the
  // effectiveTab computation in build()).
  int _resultTab = 1;

  // Guards double-tap while a tapped destination's real coordinates are
  // being resolved — same geocode-then-navigate pattern _CollectionCard
  // (home_screen.dart) uses for the same reason.
  bool _resolvingDestination = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so the Suggestions/Browse split (which reads
    // _focusNode.hasFocus at build time) actually reacts to the field being
    // tapped into or away from.
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() {
        _query = value;
        _resultTab = _defaultTabFor(value);
      });

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
      _resultTab = 1;
    });
  }

  /// Destinations wins the default tab only on a confident (exact place
  /// name) match — e.g. typing "Hanoi" in full; a tour wins on the same
  /// exact-name-match confidence (e.g. typing a tour's full title),
  /// checked second so a destination match still takes priority if a query
  /// happens to match both exactly. Anything less certain defaults to
  /// Gems, matching this screen's existing default before Destinations (and
  /// now Tours) existed — Gems stays the universal fallback, not a third
  /// competing exact-match check. Either default can still be overridden at
  /// build time if the chosen tab turns out to have zero results — see the
  /// effectiveTab computation in build().
  int _defaultTabFor(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 1;
    final exactDest =
        _matchingDestinations(query).any((d) => d.cityName.toLowerCase() == q);
    if (exactDest) return 0;
    final exactTour = context
        .read<TourProvider>()
        .tours
        .any((t) => t.name.trim().toLowerCase() == q);
    if (exactTour) return 2;
    return 1;
  }

  /// [tours] narrowed to [query] — substring, case-insensitive, matching
  /// [_matchingDestinations]'s own convention. Tour has no
  /// city/location field to also match against (see lib/models/tour.dart —
  /// deliberately no structured location, same reasoning as its other
  /// free-text-only fields), so this only ever matches on name.
  List<Tour> _matchingTours(List<Tour> tours, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return tours;
    return tours.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  /// [_query], matched against the same curated country/city list
  /// (curated_destinations.dart) — substring, case-insensitive, matching
  /// gemMatchesSearch's own convention elsewhere in this app. Returns both a
  /// country's top (photo) cities and its secondary (no-photo) chip cities.
  List<_DestinationMatch> _matchingDestinations(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_DestinationMatch>[];
    for (final region in CuratedDestinations.regions) {
      for (final country in region.countries) {
        for (final city in country.topCities) {
          if (city.name.toLowerCase().contains(q)) {
            out.add(_DestinationMatch(
                cityName: city.name,
                countryName: country.name,
                photoUrl: city.photoUrl));
          }
        }
        for (final more in country.moreCities) {
          if (more.toLowerCase().contains(q)) {
            out.add(_DestinationMatch(
                cityName: more, countryName: country.name, photoUrl: null));
          }
        }
      }
    }
    return out;
  }

  /// Resolves [cityName]'s real coordinates via [GeocodingService] then
  /// pushes the same `/destinations/explore` route every destination-tap
  /// flow in this app uses — one destination detail screen, reached the
  /// same way from either path. Falls back to the bare city name with no
  /// coordinates if geocoding fails rather than blocking navigation over a
  /// network hiccup.
  Future<void> _openDestination(BuildContext context, String cityName) async {
    if (_resolvingDestination) return;
    setState(() => _resolvingDestination = true);
    final results = await GeocodingService().search(cityName);
    if (!mounted) return;
    setState(() => _resolvingDestination = false);

    final place = results.isNotEmpty ? results.first : null;
    final label = (place != null && place.fullName.isNotEmpty)
        ? place.fullName
        : cityName;

    final uri = Uri(path: '/destinations/explore', queryParameters: {
      'name': label,
      if (place?.lat != null) 'lat': '${place!.lat}',
      if (place?.lng != null) 'lng': '${place!.lng}',
    });
    if (context.mounted) context.push(uri.toString());
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
    final tourProv = context.watch<TourProvider>();
    final hasFilter = _query.isNotEmpty || _selectedCat != 'all';
    final showSuggestions = !hasFilter && _focusNode.hasFocus;
    final featured =
        gem.featured; // GLOBAL trending — independent of any filter

    final items = gem.search(query: _query, category: _selectedCat);

    // Destinations/Gems/Tours tab split — only meaningful once there's a
    // query to match a place/tour name against; a bare category filter
    // (e.g. tapping "Hiking" with an empty search field) has no
    // destination or tour side to show, so it stays exactly what this
    // screen already did before these tabs existed: one Gems grid, no tabs.
    final showDestTabs = _query.trim().isNotEmpty;
    final destMatches = showDestTabs
        ? _matchingDestinations(_query)
        : const <_DestinationMatch>[];
    final tourMatches = showDestTabs
        ? _matchingTours(tourProv.tours, _query)
        : const <Tour>[];
    var effectiveTab = _resultTab;
    if (showDestTabs) {
      final gemsEmpty = items.isEmpty;
      final destEmpty = destMatches.isEmpty;
      final toursEmpty = tourMatches.isEmpty;
      // The active tab having nothing to show, while another one does,
      // shows a populated tab instead of a dead-empty screen. Falls through
      // Destinations -> Tours (or Tours -> Destinations) in that order only
      // as a second choice, matching _defaultTabFor's own
      // Destinations-before-Tours priority.
      if (effectiveTab == 1 && gemsEmpty) {
        if (!destEmpty) {
          effectiveTab = 0;
        } else if (!toursEmpty) {
          effectiveTab = 2;
        }
      } else if (effectiveTab == 0 && destEmpty) {
        if (!gemsEmpty) {
          effectiveTab = 1;
        } else if (!toursEmpty) {
          effectiveTab = 2;
        }
      } else if (effectiveTab == 2 && toursEmpty) {
        if (!destEmpty) {
          effectiveTab = 0;
        } else if (!gemsEmpty) {
          effectiveTab = 1;
        }
      }
    }
    // Category chips only apply to Gems — hide them while Destinations or
    // Tours is the tab actually on screen so there's no filter control
    // sitting there that visibly does nothing.
    final showGemChips = !showDestTabs || effectiveTab == 1;

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: Stack(
        children: [
          CustomScrollView(
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
                  style:
                      const TextStyle(color: AppTheme.lightInk, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search places, activities, gems…',
                    hintStyle: const TextStyle(
                        color: AppTheme.lightMute, fontSize: 15),
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
                  preferredSize: Size.fromHeight(
                      (showDestTabs ? 44 : 0) + (showGemChips ? 56 : 0)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDestTabs)
                        _ResultTabBar(
                          active: effectiveTab,
                          destCount: destMatches.length,
                          gemCount: items.length,
                          tourCount: tourMatches.length,
                          onSelect: (t) => setState(() => _resultTab = t),
                        ),
                      if (showGemChips)
                        CategoryChipRow(
                          selected: _selectedCat,
                          onSelect: (cat) => setState(() => _selectedCat = cat),
                        ),
                    ],
                  ),
                ),
              ),
              if (showSuggestions)
                _SuggestionsSlivers(
                    popular: gem.popularTerms, onChip: _applyChip)
              else if (showDestTabs && effectiveTab == 0)
                _DestinationResultsSlivers(
                  matches: destMatches,
                  query: _query,
                  onTap: (cityName) => _openDestination(context, cityName),
                )
              else if (showDestTabs && effectiveTab == 2)
                _TourResultsSlivers(matches: tourMatches, query: _query)
              else if (hasFilter)
                _ResultsSlivers(
                  gem: gem,
                  items: items,
                  onSave: _comingSoonSave,
                )
              else
                _BrowseSlivers(
                  gem: gem,
                  featured: featured,
                  items: items,
                  onSave: _comingSoonSave,
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
          if (_resolvingDestination)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Suggestions state: just the Popular Searches chips — the category grid
/// Screen A used to show here is gone, since the same categories are already
/// one persistent bar above ([CategoryChipRow]), not worth showing twice.
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

/// Browse state (default landing view): Featured Gems rail + All Gems grid.
class _BrowseSlivers extends StatelessWidget {
  const _BrowseSlivers({
    required this.gem,
    required this.featured,
    required this.items,
    required this.onSave,
  });

  final GemProvider gem;
  final List<Gem> featured;
  final List<Gem> items;
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
        _ItemGridSliver(gem: gem, items: items, onSave: onSave),
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
    required this.onSave,
  });

  final GemProvider gem;
  final List<Gem> items;
  final void Function(BuildContext context) onSave;

  @override
  Widget build(BuildContext context) {
    return _ItemGridSliver(gem: gem, items: items, onSave: onSave);
  }
}

/// Loading/error/empty/data states for the 2-column Gems grid — shared by
/// both Browse's "All Gems" section and the Results state.
class _ItemGridSliver extends StatelessWidget {
  const _ItemGridSliver({
    required this.gem,
    required this.items,
    required this.onSave,
  });

  final GemProvider gem;
  final List<Gem> items;
  final void Function(BuildContext context) onSave;

  @override
  Widget build(BuildContext context) {
    if (gem.loading) {
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
          (ctx, i) =>
              GemResultCard(gem: items[i], onSave: () => onSave(ctx)),
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

/// Destinations / Gems / Tours tab strip — only shown once there's a query
/// to match a place/tour name against (see [_ListingsScreenState.build]).
/// Counts are shown on every tab always, including 0, so a de-emphasized
/// "Tours 0" reads as "I checked, there's nothing here" rather than a
/// second empty-state screen — the active tab auto-switches to whichever
/// side actually has results (see the effectiveTab computation in
/// build()), so a 0 badge should only ever appear on an *inactive* tab in
/// practice.
class _ResultTabBar extends StatelessWidget {
  const _ResultTabBar({
    required this.active,
    required this.destCount,
    required this.gemCount,
    required this.tourCount,
    required this.onSelect,
  });

  final int active; // 0 = Destinations, 1 = Gems, 2 = Tours
  final int destCount;
  final int gemCount;
  final int tourCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(child: _tab(context, 0, 'Destinations', destCount)),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, 1, 'Gems', gemCount)),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, 2, 'Tours', tourCount)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, String label, int count) {
    final isActive = active == index;
    final emphasize = count > 0 || isActive;
    return GestureDetector(
      onTap: () => onSelect(index),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppTheme.lightInk : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isActive
                ? Colors.white
                : (emphasize ? AppTheme.lightInk : AppTheme.lightMute),
          ),
        ),
      ),
    );
  }
}

/// Destinations tab body — one match per curated city whose name contains
/// the query (see [_ListingsScreenState._matchingDestinations]).
class _DestinationResultsSlivers extends StatelessWidget {
  const _DestinationResultsSlivers({
    required this.matches,
    required this.query,
    required this.onTap,
  });

  final List<_DestinationMatch> matches;
  final String query;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyStateView(
          text: 'No destinations match "$query".',
          icon: Icons.map_outlined,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) =>
            _DestinationRow(match: matches[i], onTap: onTap),
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.match, required this.onTap});

  final _DestinationMatch match;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${match.cityName}, ${match.countryName}',
      child: GestureDetector(
        onTap: () => onTap(match.cityName),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: match.photoUrl != null
                      ? AppNetworkImage(url: match.photoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          alignment: Alignment.center,
                          child: const Icon(Icons.location_city,
                              color: AppTheme.primary, size: 22),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(match.cityName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.lightInk)),
                    const SizedBox(height: 2),
                    Text(match.countryName,
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.lightMute),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tours tab — same real [Tour] data (TourProvider.tours) the standalone
/// Tours screen (tours_list_screen.dart) uses, no separate query. Row shape
/// mirrors [_DestinationRow] (thumbnail + name + meta + chevron) rather than
/// [tours_list_screen.dart]'s own grid [TourCard] — this tab renders a
/// vertical results list like Destinations, not a grid, so the row shape is
/// the better structural match; the underlying data source is still shared.
class _TourResultsSlivers extends StatelessWidget {
  const _TourResultsSlivers({required this.matches, required this.query});

  final List<Tour> matches;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyStateView(
          text: 'No tours match "$query".',
          icon: Icons.explore_outlined,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _TourRow(tour: matches[i]),
      ),
    );
  }
}

class _TourRow extends StatelessWidget {
  const _TourRow({required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      'From ${tour.currency} ${tour.priceFrom}',
      if (tour.durationLabel != null && tour.durationLabel!.isNotEmpty)
        tour.durationLabel!,
    ].join(' · ');
    return Semantics(
      button: true,
      label: tour.name,
      child: GestureDetector(
        onTap: () => context.push('/tours/${tour.id}'),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: tour.coverPhoto != null
                      ? AppNetworkImage(
                          url: tour.coverPhoto!, fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          alignment: Alignment.center,
                          child: Text(tour.emoji,
                              style: const TextStyle(fontSize: 22)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tour.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.lightInk)),
                    const SizedBox(height: 2),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 12)),
                  ],
                ),
              ),
              // Same "never automatic" rule as everywhere else isCurated is
              // read (see Tour.isCurated's own doc comment) — this badge is
              // purely a display of that flag, not a second place it could
              // be derived from.
              if (tour.isCurated)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('TOP PICK',
                      style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                ),
              const Icon(Icons.chevron_right, color: AppTheme.lightMute),
            ],
          ),
        ),
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

class GemResultCard extends StatelessWidget {
  const GemResultCard({super.key, required this.gem, required this.onSave});

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


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import 'asset_card.dart';

/// Below this many location-tagged matches, the panel gives up on the
/// location filter and shows the whole catalogue (with a banner). A trip whose
/// city has only one or two tagged gems is better served by the full list than
/// by a near-empty pane — the user came here to *build*, not to admire scarcity.
const int _locationFallbackThreshold = 3;

/// Left pane of the Trip Builder: a searchable, category-filterable list of
/// gems, each a [AssetCard] the user drags onto the itinerary canvas.
///
/// Reads two providers: [TripProvider] for the active trip's location (the
/// default filter) and [GemProvider] for the catalogue. Location filtering is
/// soft — see [_locationFallbackThreshold]: too few local gems and we fall back
/// to the full list, flagging it so cards annotate their own location.
class DiscoveryPanel extends StatefulWidget {
  const DiscoveryPanel({super.key, required this.tripId});
  final String tripId;

  @override
  State<DiscoveryPanel> createState() => _DiscoveryPanelState();
}

class _DiscoveryPanelState extends State<DiscoveryPanel> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _activeCategory = 'all';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Debounced so a fast typist doesn't rebuild the list on every keystroke.
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  bool _matchesSearch(Gem g) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return g.gemName.toLowerCase().contains(q) ||
        (g.tagline?.toLowerCase().contains(q) ?? false) ||
        (g.description?.toLowerCase().contains(q) ?? false);
  }

  /// Filters [source] to gems whose location contains every token of [location]
  /// (whitespace-split, case-insensitive). If fewer than
  /// [_locationFallbackThreshold] match, returns the full [source] with
  /// `fellBack: true` and the count that *would* have matched — the caller shows
  /// a banner and asks cards to annotate their location.
  ({List<Gem> gems, bool fellBack, int matched}) _locationFiltered(
      List<Gem> source, String? location) {
    // TODO(gemsIn): this token-substring match runs client-side over the whole
    // catalogue. Promote to a pure GemProvider.gemsIn(location) read once gems
    // are queried server-side, keeping the fallback-threshold logic here.
    if (location == null || location.trim().isEmpty) {
      return (gems: source, fellBack: false, matched: source.length);
    }
    final tokens = location.toLowerCase().split(RegExp(r'\s+'));
    final local = source.where((g) {
      final loc = g.gemLocation?.toLowerCase();
      if (loc == null || loc.isEmpty) return false;
      return tokens.every(loc.contains);
    }).toList();
    if (local.length < _locationFallbackThreshold) {
      return (gems: source, fellBack: true, matched: local.length);
    }
    return (gems: local, fellBack: false, matched: local.length);
  }

  @override
  Widget build(BuildContext context) {
    final location =
        context.select<TripProvider, String?>((p) => p.activeTrip?.location);
    // TODO(provider): search + category + location all filter this in-memory
    // list. Fine for the ~46-gem catalogue; promote to a server-side query
    // (GemProvider) once the catalogue grows past ~500 and client filtering
    // stops being free.
    final allGems = context.watch<GemProvider>().allGems;

    // Location gate first, so the fallback decision is made on the raw
    // catalogue — search/category narrow *within* whatever set we settled on.
    final located = _locationFiltered(allGems, location);

    final filtered = located.gems.where((g) {
      final catOk =
          _activeCategory == 'all' || g.category?.toLowerCase() == _activeCategory;
      return catOk && _matchesSearch(g);
    }).toList();

    final hasFilters = _query.isNotEmpty || _activeCategory != 'all';

    return Container(
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(location: location, count: filtered.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SearchField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
            ),
          ),
          _CategoryChips(
            active: _activeCategory,
            onSelected: (c) => setState(() => _activeCategory = c),
          ),
          if (located.fellBack)
            _FallbackBanner(location: location!, matched: located.matched),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    hasFilters: hasFilters,
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() {
                        _query = '';
                        _activeCategory = 'all';
                      });
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => AssetCard(
                      gem: filtered[i],
                      showLocation: located.fellBack,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Panel title + live match count. The title owns the location phrasing so the
/// cards below can stay lean (this is why [AssetCard.showLocation] defaults off).
class _Header extends StatelessWidget {
  const _Header({required this.location, required this.count});

  final String? location;
  final int count;

  @override
  Widget build(BuildContext context) {
    final title = location != null && location!.isNotEmpty
        ? 'Discover $location'
        : 'Discover';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Rounded search field. Kept dumb: state lives in the panel, this just relays
/// changes so the debounce timer stays in one place.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search gems',
        hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        prefixIcon: const Icon(Icons.search,
            color: AppTheme.textSecondary, size: 20),
        filled: true,
        fillColor: AppTheme.surface2,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

/// Horizontally scrolling category filter: 'All' + [Gem.categories]. Panel-local
/// state — this is a view filter, nothing persists.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.active, required this.onSelected});

  final String active;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = ['all', ...Gem.categories];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = items[i];
          final selected = c == active;
          final label = c == 'all' ? 'All' : c[0].toUpperCase() + c.substring(1);
          return GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : AppTheme.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.divider),
              ),
              child: Text(label,
                  style: TextStyle(
                      color:
                          selected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }
}

/// Shown when the location filter fell back to the full catalogue. Explains why
/// the list is broader than the trip's city and why cards now carry a location.
class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner({required this.location, required this.matched});

  final String location;
  final int matched;

  @override
  Widget build(BuildContext context) {
    final lead = matched == 0
        ? 'No gems tagged $location yet.'
        : matched == 1
            ? 'Only 1 gem tagged $location.'
            : 'Only $matched gems tagged $location.';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$lead Showing all gems below.',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Empty result. Distinguishes "your filters excluded everything" (offer a
/// reset) from "the catalogue itself is empty" (nothing to reset).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore,
                color: AppTheme.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'No gems match your filters.'
                  : 'No gems to show yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onClear,
                child: const Text('Clear filters',
                    style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

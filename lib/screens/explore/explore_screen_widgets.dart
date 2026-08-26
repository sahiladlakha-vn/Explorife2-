part of 'explore_screen.dart';

// ─────────────────────────────────────────
// SMALL CONTROLS
// ─────────────────────────────────────────
class _MapControl extends StatelessWidget {
  final Widget child;
  const _MapControl({required this.child});

  @override
  Widget build(BuildContext context) {
    // Frosted-glass control panel: a real backdrop blur of the map underneath,
    // with a translucent dark tint + hairline border so the icons stay legible
    // over any basemap (light outdoors, dark, or satellite imagery).
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconHit extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _IconHit({required this.icon, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

/// One Dawn/Day/Dusk/Night option in the layers sheet's lighting row (Mapbox
/// Standard Style's own preset names — see explore_screen.dart's
/// _autoLightPreset and mapbox_globe.js's applyLightPreset). Material has no
/// distinct dawn/dusk glyphs, so dawn/dusk share a twilight icon; day/night
/// get their own — the label text still disambiguates dawn from dusk.
class _LightPresetChip extends StatelessWidget {
  const _LightPresetChip({required this.preset, required this.selected, required this.onTap});

  final String preset;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (preset) {
        'dawn' || 'dusk' => Icons.wb_twilight,
        'day' => Icons.wb_sunny,
        _ => Icons.nightlight_round,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.lightBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 16, color: selected ? Colors.white : AppTheme.lightMute),
            const SizedBox(width: 6),
            Text(preset[0].toUpperCase() + preset.substring(1),
                style: GoogleFonts.fredoka(
                    color: selected ? Colors.white : AppTheme.lightInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// BOTTOM SHEET — discovery feed
//
// A draggable sheet over the map with two named snap points (see [SheetSnap]):
// at `peek` it shows a sticky header + a horizontal carousel of [GemCard]s and
// a "See all" button; at `expanded` the same cards reflow into a full-width
// vertical list. The sheet owns its [DraggableScrollableController] and derives
// the current snap from the live extent, so layout follows the drag with no
// duplicated thresholds.
// ─────────────────────────────────────────
class _BottomSheet extends StatefulWidget {
  final GemProvider gemProv;
  final IconData Function(String?) iconFor;

  /// Tapping a list item SELECTS that gem (id) — the sheet collapses itself to
  /// peek first, then this fires so the host updates the shared selection
  /// (deck + pin). The sheet is the full-list surface; it no longer opens the
  /// detail directly.
  final ValueChanged<String> onGemSelected;

  /// Fires when the sheet settles on a new named detent, so the host can show
  /// the floating deck at peek and hide it once the full list takes over.
  final ValueChanged<SheetSnap> onSnap;
  final VoidCallback onSort;
  final String? city;
  final double? userLat, userLng;

  /// Logical px reserved at the TOP that the sheet must never rise into — the
  /// filter-chip row's bottom edge plus [kSheetTopGapBelowChips]. Caps the full
  /// detent so the expanding sheet always keeps clear air below the chips.
  final double topReservedPx;

  /// Reports how many CSS pixels of the map the sheet currently covers (its
  /// height from the bottom edge), so the host can shield the web map's canvas
  /// under that strip from gesture bleed. Fires on every drag frame + snap.
  final ValueChanged<double> onCoverage;
  const _BottomSheet({
    required this.gemProv,
    required this.iconFor,
    required this.onGemSelected,
    required this.onSnap,
    required this.onSort,
    required this.onCoverage,
    required this.topReservedPx,
    this.city,
    this.userLat,
    this.userLng,
  });

  @override
  State<_BottomSheet> createState() => _BottomSheetState();
}

class _BottomSheetState extends State<_BottomSheet> {
  final _controller = DraggableScrollableController();
  // Derived view of the controller extent (recomputed each drag frame via
  // SheetSnap.nearestFor) — the controller stays the single source of truth;
  // this only selects which body layout to show. Landing is always peek.
  SheetSnap _snap = SheetSnap.landing;
  // The MEASURED peek fraction (header-hugging), recomputed in build from the
  // available height and read back by the drag listener so snap derivation uses
  // the same value the sheet was built with.
  double _peek = SheetSnap.peek.size;
  // The CAPPED full fraction, recomputed in build so the expanded sheet stops a
  // fixed gap below the floating chip row (see SheetSnap.fullFractionFor). Read
  // back by the drag listener so snap derivation matches the built max.
  double _full = SheetSnap.full.size;

  @override
  void initState() {
    super.initState();
    // Each Map-tab visit recreates this State, so we always land at the
    // content-hugging peek — cards are revealed by dragging, never at rest.
    _snap = SheetSnap.landing;
    _controller.addListener(_onDrag);
    // Push the initial coverage once the sheet has settled at its peek size on
    // the first frame (the controller only notifies on subsequent changes).
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushCoverage());
  }

  @override
  void dispose() {
    _controller.removeListener(_onDrag);
    _controller.dispose();
    super.dispose();
  }

  // Derive the logical snap from the live extent so the body layout (carousel
  // vs. list) tracks the drag without re-deriving thresholds anywhere else.
  void _onDrag() {
    if (!_controller.isAttached) return;
    final next = SheetSnap.nearestFor(_controller.size, _peek, _full);
    if (next != _snap) {
      setState(() => _snap = next);
      widget.onSnap(next); // host shows the deck at peek, hides it at full
    }
    _pushCoverage();
  }

  /// Drops the sheet back to the collapsed peek so the floating deck + map
  /// return after a list item is chosen.
  void _collapse() => _controller.animateTo(
        _peek,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );

  // Forward the sheet's live pixel height so the host can size the map's
  // gesture shield to exactly the covered strip.
  void _pushCoverage() {
    if (!_controller.isAttached) return;
    widget.onCoverage(_controller.pixels);
  }

  String? _distanceFor(Gem g) {
    if (g.latitude == null || g.longitude == null) return null;
    // Read the SAME anchor the list is sorted by (user location, else active-
    // area centre), so a row's pill number agrees with its nearest-first slot.
    final anchor = widget.gemProv
        .feedAnchor(userLat: widget.userLat, userLng: widget.userLng);
    if (anchor == null) return null;
    return gemDistanceLabel(Geolocator.distanceBetween(
        anchor.$1, anchor.$2, g.latitude!, g.longitude!));
  }

  @override
  Widget build(BuildContext context) {
    final gemProv = widget.gemProv;
    // The sheet (list + count) reads the ACTIVE-AREA feed: the bbox of the
    // launch city or a searched place, distance-sorted nearest-first off the
    // shared feed anchor (user location, else area centre). Map markers stay
    // global (a superset) so panning still reveals pins outside the area —
    // only this sheet narrows.
    final gems =
        gemProv.feedGems(userLat: widget.userLat, userLng: widget.userLng);
    // Measure the available sheet height so the peek detent can HUG the thin
    // peek strip (handle + single meta line) exactly — no magic fraction, no
    // blank band below the line. The filter chips now live OUTSIDE the sheet
    // (a floating row under the search bar), so the strip is just one line.
    return LayoutBuilder(builder: (context, constraints) {
      _peek = SheetSnap.peekFractionFor(
        headerHeight: kSheetPeekHeight,
        availableHeight: constraints.maxHeight,
      );
      // Cap the full detent so the sheet's top edge stops a fixed gap below the
      // chip row (an independent layer above the map), never clipping it. On a
      // viewport too short to honour the cap, prefer a shorter sheet — but never
      // below peek, so the DraggableScrollableSheet's min/max bounds stay valid.
      _full = SheetSnap.fullFractionFor(
        topReservedPx: widget.topReservedPx,
        availableHeight: constraints.maxHeight,
      );
      if (_full < _peek) _full = _peek;
      return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: _peek,
      minChildSize: _peek,
      maxChildSize: _full,
      snap: true,
      snapSizes: SheetSnap.snapSizesFor(_peek, _full),
      builder: (context, scrollController) {
        // On web the map is a Mapbox GL JS platform view (an HTML canvas) that
        // captures DOM pointer events directly, bypassing Flutter's gesture
        // arena — so drags/scrolls over this sheet would otherwise also pan the
        // map underneath. PointerInterceptor lays a transparent HTML element
        // over the sheet's area to absorb those events (no-op on native).
        return PointerInterceptor(
          child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.sheetSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -6)),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _FeedHeaderDelegate(
                  city: widget.city,
                  total: gemProv.feedCount(gemProv.selectedCategory),
                  focused: gemProv.hasActiveArea,
                  areaLabel: gemProv.activeAreaLabel,
                  isPeek: _snap.isPeek,
                ),
              ),
              if (gems.isEmpty)
                SliverToBoxAdapter(child: _emptyState())
              else if (_snap.isFull)
                ..._listSlivers(gems),
              // peek → thin strip only (city + count + "drag up"); the floating
              // card deck + map are the hero. Drag up for the full list.
            ],
          ),
          ),
        );
      },
      );
    });
  }

  // ── full: full-width vertical list of the same cards ──
  // Tapping a list item collapses the sheet to peek and SELECTS the gem (the
  // host then syncs the deck + pin) rather than opening the detail outright.
  // The big Bebas city title + sort button live HERE (the expanded view), not
  // in the thin pinned peek strip.
  List<Widget> _listSlivers(List<Gem> gems) => [
        SliverToBoxAdapter(child: _fullListHeader()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final gem = gems[i];
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                  child: GemCard(
                    gem: gem,
                    categoryIcon: widget.iconFor(gem.category),
                    variant: GemCardVariant.full,
                    isSaved: widget.gemProv.isSaved(gem.id),
                    distanceLabel: _distanceFor(gem),
                    onTap: () {
                      _collapse();
                      widget.onGemSelected(gem.id);
                    },
                    onToggleSave: () =>
                        context.read<GemProvider>().toggleSave(gem),
                  ),
                );
              },
              childCount: gems.length,
            ),
          ),
        ),
      ];

  // The expanded list's hero header: the big Bebas city title + the sort
  // button. Shown only at full (above the vertical list), so the collapsed peek
  // strip stays a single thin line.
  Widget _fullListHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                (widget.city ?? 'Hidden Gems').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bebasNeue(
                  fontSize: 30,
                  color: AppTheme.sheetInk,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: widget.onSort,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.sheetChipIdle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.sheetChipBorder),
                ),
                child: const Icon(Icons.tune, size: 20, color: AppTheme.sheetInk),
              ),
            ),
          ],
        ),
      );

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        child: Center(
          child: Text(
            'No gems in this area yet — drag the map to explore, or drop one.',
            textAlign: TextAlign.center,
            style: GoogleFonts.fredoka(
                fontSize: 13, color: AppTheme.sheetSubInk),
          ),
        ),
      );
}

/// Pinned THIN peek strip for the feed sheet: just the grab handle + a single
/// "<City> · <n> spots · drag up for list" line. The big Bebas city title + the
/// sort button moved into the expanded full-list header, and the category chip
/// rail moved OUT of the sheet entirely (a floating [_FilterChipsBar] under the
/// search bar), so the collapsed sheet hugs this one strip with no blank band.
class _FeedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String? city;
  // Immutable VALUE snapshots taken in _BottomSheetState.build. Critically NOT
  // the live GemProvider: a delegate holding the shared notifier would compare
  // `old.gemProv.x != gemProv.x` on the same instance — always false — and the
  // pinned strip would freeze at its first (empty) frame. Snapshots make
  // shouldRebuild compare real values, so the count tracks the data.
  final int total; // count — follows the selected category
  // Whether the feed is narrowed to an active area; drives the meta-line wording
  // ("in <place>" vs "across the map") when expanded.
  final bool focused;
  // The active area's label (e.g. "Ho Chi Minh City"); names the scope on the
  // meta line when focused. Null falls back to a generic "in this area".
  final String? areaLabel;
  // At peek the meta line hints "drag up for list" (the list is hidden); at
  // full it shows the focus-scope label instead.
  final bool isPeek;

  _FeedHeaderDelegate({
    required this.city,
    required this.total,
    required this.focused,
    required this.areaLabel,
    required this.isPeek,
  });

  // The peek detent is measured from this same value, so the strip the user
  // sees at rest and the height peek hugs are guaranteed to be the same number.
  static const double _height = kSheetPeekHeight;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(covariant _FeedHeaderDelegate old) =>
      old.city != city ||
      old.total != total ||
      old.focused != focused ||
      old.areaLabel != areaLabel ||
      old.isPeek != isPeek;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _height,
      decoration: const BoxDecoration(
        color: AppTheme.sheetSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.sheetHandle,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _metaLine(),
          ),
          const SizedBox(height: 11),
        ],
      ),
    );
  }

  Widget _metaLine() {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: city ?? 'Hidden Gems',
            style: GoogleFonts.fredoka(
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: AppTheme.sheetInk,
            ),
          ),
          TextSpan(
            text: total == 1 ? '  ·  $total spot  ·  ' : '  ·  $total spots  ·  ',
            style: GoogleFonts.fredoka(
              fontSize: 13,
              height: 1.25,
              color: AppTheme.sheetSubInk,
            ),
          ),
          TextSpan(
            // At peek the list is hidden behind the floating deck, so hint how
            // to reach it. At full, name the feed scope instead: when focused on
            // an active area the feed is bbox-scoped to that place, so name it;
            // otherwise it spans every loaded gem and "across the map" is the
            // honest label (never "nearby", which would lie next to a 3,000 km
            // distance pill).
            text: isPeek
                ? 'drag up for list'
                : (focused
                    ? 'in ${areaLabel ?? 'this area'}'
                    : 'across the map'),
            style: GoogleFonts.fredoka(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Floating horizontal filter row, MOUNTED UNDER THE SEARCH BAR (no longer
/// inside the sheet). White pills over the map; the active category turns
/// orange with a count badge. Reads + writes the SAME [GemProvider] filter
/// state the markers and deck draw from, so relocating it changed only where
/// the chips render, never what they control. A right-edge fade hints the row
/// scrolls horizontally.
class _FilterChipsBar extends StatelessWidget {
  final GemProvider gemProv;
  final IconData Function(String?) iconFor;
  const _FilterChipsBar({required this.gemProv, required this.iconFor});

  @override
  Widget build(BuildContext context) {
    final chipCounts = <String, int>{
      'all': gemProv.feedCount('all'),
      for (final c in Gem.categories) c: gemProv.feedCount(c),
    };
    final selected = gemProv.selectedCategory;
    return SizedBox(
      height: kFilterChipBarHeight,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.92, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            _FilterChip(
              icon: Icons.auto_awesome,
              label: 'All Gems',
              count: chipCounts['all'] ?? 0,
              selected: selected == 'all',
              onTap: () => context.read<GemProvider>().selectCategory('all'),
            ),
            ...Gem.categories.map((cat) => _FilterChip(
                  icon: iconFor(cat),
                  label: cat[0].toUpperCase() + cat.substring(1),
                  count: chipCounts[cat] ?? 0,
                  selected: selected == cat,
                  onTap: () =>
                      context.read<GemProvider>().selectCategory(cat),
                )),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.sheetInk;
    // The visible pill is compact (~32px) but the GestureDetector wraps a 44px
    // SizedBox so the tap target stays finger-friendly even though the chip
    // reads shorter.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        margin: const EdgeInsets.only(right: 8),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.sheetSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.sheetChipBorder,
            ),
            // The chips now float over the map, so a soft shadow keeps the
            // white idle pills legible over any basemap.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? Colors.white : AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.fredoka(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppTheme.sheetChipIdle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.fredoka(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.sheetSubInk,
                  ),
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
// FLOATING CARD DECK — primary browse surface over the map
//
// A horizontally swipeable PageView of horizontal [GemCard]s (deck variant)
// floating above the peek sheet. Its gem set is the SAME filtered set the map
// markers draw from (the host passes `gemProv.mappableGems`), so the deck and
// the pins can never disagree. Swiping is reported via [onSwipe] (the host then
// flies the map to that pin + highlights it); tapping a card opens its detail
// via [onCardTap]. The host hides this widget entirely when there are no gems.
// ─────────────────────────────────────────
class _GemDeck extends StatelessWidget {
  final List<Gem> gems;
  final PageController controller;
  final GemProvider gemProv;
  final IconData Function(String?) iconFor;
  final String? selectedId;
  // The deck's distance anchor — user location when known, else the viewport
  // centre (from GemProvider.deckAnchor). Sort order and the per-card pill read
  // this SAME anchor, so a card's position always matches the number it shows.
  final double? anchorLat, anchorLng;
  final ValueChanged<Gem> onCardTap;
  final ValueChanged<String> onSwipe;

  const _GemDeck({
    required this.gems,
    required this.controller,
    required this.gemProv,
    required this.iconFor,
    required this.selectedId,
    required this.anchorLat,
    required this.anchorLng,
    required this.onCardTap,
    required this.onSwipe,
  });

  String? _distanceFor(Gem g) {
    if (anchorLat == null ||
        anchorLng == null ||
        g.latitude == null ||
        g.longitude == null) {
      return null;
    }
    return gemDistanceLabel(Geolocator.distanceBetween(
        anchorLat!, anchorLng!, g.latitude!, g.longitude!));
  }

  @override
  Widget build(BuildContext context) {
    // Card height + room for the card's drop shadow above/below.
    return SizedBox(
      height: GemCard.deckHeight + 22,
      child: PageView.builder(
        controller: controller,
        itemCount: gems.length,
        padEnds: true,
        onPageChanged: (i) {
          if (i >= 0 && i < gems.length) onSwipe(gems[i].id);
        },
        itemBuilder: (_, i) {
          final gem = gems[i];
          return Padding(
            // Full-width card (viewportFraction 1.0) with symmetric side margins
            // so it's contained, not clipped; vertical padding leaves the card's
            // drop shadow room above/below.
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: GemCard(
              gem: gem,
              categoryIcon: iconFor(gem.category),
              variant: GemCardVariant.deck,
              isSaved: gemProv.isSaved(gem.id),
              distanceLabel: _distanceFor(gem),
              onTap: () => onCardTap(gem),
              onToggleSave: () => context.read<GemProvider>().toggleSave(gem),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
// GEM DETAIL SHEET (slides up when a marker is tapped)
//
// A draggable modal that surfaces the full gem story in place, so the user
// doesn't have to leave the map: hero, title + address, stats, description,
// creator insights, key gear, and Like / Save / Navigate actions.
//
// NOTE: rating, saves, insights and gear are illustrative — the `saved_gems`
// table has no columns for them yet. They are derived deterministically from
// the gem id (same seeded-placeholder convention used for carousel images) so
// each gem shows stable values. Real data can be wired once the schema grows.
// ─────────────────────────────────────────
class _GemDetailSheet extends StatefulWidget {
  final Gem gem;
  final IconData icon;
  final double? userLat, userLng;
  const _GemDetailSheet({
    required this.gem,
    required this.icon,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<_GemDetailSheet> createState() => _GemDetailSheetState();
}

class _GemDetailSheetState extends State<_GemDetailSheet> {
  bool _liked = false;
  bool _saved = false;

  int get _idHash => widget.gem.id.codeUnits.fold(0, (a, b) => a + b);
  double get _rating => 4.0 + (_idHash % 10) / 10.0; // 4.0–4.9

  String get _savesLabel {
    final n = 120 + (_idHash * 7) % 2400; // 120–2519
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K saves';
    return '$n saves';
  }

  String? get _distanceLabel {
    final g = widget.gem;
    if (widget.userLat == null ||
        widget.userLng == null ||
        g.latitude == null ||
        g.longitude == null) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
        widget.userLat!, widget.userLng!, g.latitude!, g.longitude!);
    if (meters < 1000) return '~${meters.round()} m';
    return '~${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
  }

  Future<void> _navigate() async {
    final g = widget.gem;
    if (g.latitude == null || g.longitude == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${g.latitude},${g.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final gem = widget.gem;
    final dist = _distanceLabel;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    _hero(gem),
                    const SizedBox(height: 16),
                    Text(
                      gem.gemName,
                      style: GoogleFonts.bebasNeue(
                        fontSize: 34,
                        color: const Color(0xFF111111),
                        letterSpacing: 0.5,
                        height: 1.05,
                      ),
                    ),
                    if (gem.tagline != null && gem.tagline!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        gem.tagline!,
                        style: GoogleFonts.fredoka(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.primary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (gem.gemLocation != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on,
                              size: 15, color: AppTheme.primary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              gem.gemLocation!,
                              style: GoogleFonts.fredoka(
                                fontSize: 13,
                                color: const Color(0xFF666666),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _statsRow(dist),
                    const _SheetDivider(),
                    Text(
                      gem.description ??
                          'A remarkable ${gem.displayCategory.toLowerCase()} discovered by the '
                              'Explorife community. Verified by local explorers with an '
                              'average rating of ${_rating.toStringAsFixed(1)} stars.',
                      style: GoogleFonts.fredoka(
                        fontSize: 14.5,
                        color: const Color(0xFF555555),
                        height: 1.6,
                      ),
                    ),
                    const _SheetDivider(),
                    _sectionLabel('CREATOR INSIGHTS'),
                    const SizedBox(height: 14),
                    ..._insights.map(_insightRow),
                    const _SheetDivider(),
                    _sectionLabel('KEY GEAR'),
                    const SizedBox(height: 12),
                    _gearGrid(),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/gems/${gem.id}');
                        },
                        child: Text(
                          'VIEW FULL PROFILE  →',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _footer(),
            ],
          ),
        );
      },
    );
  }

  // ── hero banner ──
  Widget _hero(Gem gem) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 170,
        width: double.infinity,
        child: gem.photoUrl != null
            ? Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                  imageUrl: gem.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFF1A1A1A)),
                  errorWidget: (_, __, ___) => _heroPlaceholder(),
                ),
                _heroBadge(),
              ])
            : Stack(fit: StackFit.expand, children: [
                _heroPlaceholder(),
                _heroBadge(),
              ]),
      ),
    );
  }

  Widget _heroPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1A0F), Color(0xFF120D08)],
          ),
        ),
        child: Center(
          child: Icon(widget.icon, size: 48, color: AppTheme.primary.withValues(alpha: 0.85)),
        ),
      );

  Widget _heroBadge() => Positioned(
        left: 12,
        top: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined,
                  size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                'EXPLORE THE MAP',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      );

  // ── stats row ──
  Widget _statsRow(String? dist) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFF8A00)),
        const SizedBox(width: 4),
        Text(
          _rating.toStringAsFixed(1),
          style: GoogleFonts.fredoka(
              fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF111111)),
        ),
        const SizedBox(width: 14),
        const Icon(Icons.bookmark_border, size: 16, color: Color(0xFF8A8A8A)),
        const SizedBox(width: 4),
        Text(
          _savesLabel,
          style: GoogleFonts.fredoka(fontSize: 13, color: const Color(0xFF8A8A8A)),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F7EC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF7CC68B)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, size: 12, color: Color(0xFF2E9E4F)),
              const SizedBox(width: 3),
              Text(
                'VERIFIED',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E9E4F),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (dist != null)
          Text(
            dist,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 12, color: const Color(0xFF8A8A8A)),
          ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFAAAAAA),
          letterSpacing: 1.5,
        ),
      );

  // Illustrative community insights (no comments table yet).
  List<_Insight> get _insights => const [
        _Insight('TM', '2h ago', 'Incredible spot. Bring a headlamp for the inner chamber.'),
        _Insight('LV', '5h ago', "Best sunrise I've ever witnessed. Go in October."),
        _Insight('AK', '1d ago', 'Trail is tough but worth every step.'),
      ];

  Widget _insightRow(_Insight i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              i.initials,
              style: GoogleFonts.fredoka(
                  fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      i.initials,
                      style: GoogleFonts.fredoka(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111111)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      i.time,
                      style: GoogleFonts.fredoka(
                          fontSize: 12, color: const Color(0xFFAAAAAA)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  i.text,
                  style: GoogleFonts.fredoka(
                      fontSize: 14, color: const Color(0xFF666666), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Illustrative gear checklist (no gear table yet).
  Widget _gearGrid() {
    const gear = [
      _Gear('Head Torch', true, true),
      _Gear('Rope (30m)', true, true),
      _Gear('First Aid Kit', true, false),
      _Gear('Water (3L)', true, true),
      _Gear('Trekking Poles', false, false),
      _Gear('Rain Jacket', false, true),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < gear.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: _gearChip(gear[i])),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < gear.length
                  ? _gearChip(gear[i + 1])
                  : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _gearChip(_Gear g) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: g.checked ? const Color(0xFFFFF1E8) : const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: g.checked ? const Color(0xFFFFD2B5) : const Color(0xFFE6E6E6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: g.checked ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: g.checked ? AppTheme.primary : const Color(0xFFCCCCCC),
                width: 2,
              ),
            ),
            child: g.checked
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              g.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fredoka(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: g.checked ? const Color(0xFF111111) : const Color(0xFF999999),
              ),
            ),
          ),
          Text(
            g.required ? 'REQ' : 'OPT',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: g.required ? AppTheme.primary : const Color(0xFFBBBBBB),
            ),
          ),
        ],
      ),
    );
  }

  // ── footer actions ──
  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _outlineAction(
              icon: _liked ? Icons.favorite : Icons.favorite_border,
              label: 'LIKE',
              active: _liked,
              onTap: () {
                setState(() => _liked = !_liked);
                _toast(_liked ? 'Liked' : 'Like removed');
              },
            ),
            const SizedBox(width: 10),
            _outlineAction(
              icon: _saved ? Icons.bookmark : Icons.bookmark_border,
              label: 'SAVE',
              active: _saved,
              onTap: () {
                setState(() => _saved = !_saved);
                _toast(_saved ? 'Saved to your spots' : 'Removed from spots');
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _navigate,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.navigation, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'NAVIGATE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineAction({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? AppTheme.primary : const Color(0xFF666666);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E2E2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Divider(height: 1, color: Color(0xFFEEEEEE)),
      );
}

class _Insight {
  final String initials, time, text;
  const _Insight(this.initials, this.time, this.text);
}

class _Gear {
  final String label;
  final bool required;
  final bool checked;
  const _Gear(this.label, this.required, this.checked);
}

/// A geographic match returned from Mapbox forward-geocoding for the search
/// dropdown's "Locations" section.
class _LocResult {
  final String name;
  final String context;
  final double? lat, lng;

  /// The place's bounding box `[west, south, east, north]` when the geocoder
  /// supplies one (cities/regions do; POIs/addresses may not). Drives the sheet
  /// active area so the feed scopes to the whole place, not a radius.
  final List<double>? bbox;
  const _LocResult({
    required this.name,
    required this.context,
    this.lat,
    this.lng,
    this.bbox,
  });
}

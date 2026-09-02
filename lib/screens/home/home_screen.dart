import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/curated_collections.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/layout/max_width_center.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../providers/tour_provider.dart';
import '../../models/gem.dart';
import '../../models/tour.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/common/photo_info_card.dart';
import '../../widgets/state_views.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // value is one of Gem.categories (or 'all') — the same taxonomy
  // ListingsScreen's own category bar filters by, so a chip tap is a real
  // filter there instead of a plain-text search-query guess. Icons reuse
  // GemCategories.iconFor so a category reads identically everywhere in the
  // app (Explore, Listings, here).
  static final List<({String value, String label, IconData icon})> _cats = [
    (value: 'all', label: 'All', icon: Icons.public),
    for (final c in Gem.categories)
      (
        value: c,
        label: c[0].toUpperCase() + c.substring(1),
        icon: GemCategories.iconFor(c),
      ),
  ];

  // Saving gems isn't persisted yet (needs a gem_saves table) — surface that
  // honestly instead of faking a local toggle that vanishes on reload.
  void _comingSoonSave(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving gems is coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: MaxWidthCenter(
        child: RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.lightCard,
          onRefresh: () => context.read<GemProvider>().refresh(),
          child: CustomScrollView(
            // alwaysScrollable so pull-to-refresh works even when content is short
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── HERO ──
              SliverToBoxAdapter(child: _Hero()),

              // ── STATS BAR ──
              SliverToBoxAdapter(child: _StatsBar()),

              // ── SEARCH + FILTERS (always visible chrome) ──
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),
                    _SearchBar(),
                    const SizedBox(height: 16),
                    _CategoryPills(
                      cats: _cats
                          .map((c) => (label: c.label, icon: c.icon))
                          .toList(),
                      // No persistent selection: a tap is a shortcut straight
                      // into ListingsScreen pre-filtered to that category —
                      // same merged Discovery experience the search bar opens,
                      // not a separate screen, so there's nothing to reflect
                      // as "currently selected" back here on Home.
                      selected: -1,
                      onSelect: (i) {
                        final cat = _cats[i].value;
                        context.go(cat == 'all'
                            ? '/listings'
                            : '/listings?category=$cat');
                      },
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),

              // ── EXPLORE IDEAS (curated collections rail) ──
              // Replaces Start Exploring / DestinationBrowserSheet. Runs no
              // retrieval of its own beyond the static collection list —
              // every card navigates straight into Search Results or
              // Destination Detail, the same screens the search bar above
              // already opens. See _CollectionCard.
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _SectionHead(title: 'EXPLORE IDEAS'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 290,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: CuratedCollections.all.length,
                    itemBuilder: (ctx, i) =>
                        _CollectionCard(collection: CuratedCollections.all[i]),
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(top: 20)),

              // ── CONTENT REGION (real gems via GemProvider) ──
              SliverToBoxAdapter(
                child: Consumer<GemProvider>(
                  builder: (context, gem, _) {
                    final featuredGems = gem.featured;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SectionHead(
                            title: 'FEATURED',
                            onSeeAll: () => context.go('/listings'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (gem.loading)
                          const FeaturedRowSkeleton()
                        else if (gem.hasError)
                          ErrorStateView(
                              onRetry: gem.refresh, message: gem.error)
                        else if (featuredGems.isEmpty)
                          const EmptyStateView(text: 'No featured gems yet.')
                        else
                          SizedBox(
                            height: 290,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: featuredGems.length,
                              itemBuilder: (ctx, i) => _FeaturedGemCard(
                                gem: featuredGems[i],
                                isTrending: gem.isTrending(featuredGems[i]),
                                onSave: () => _comingSoonSave(ctx),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // ── TOURS & EXPERIENCES (real tours via TourProvider) ──
              // Sits after Featured (free, no-commitment content) and before
              // the Community CTA below — trust-building/free content comes
              // first, Tours (paid/bookable) comes right before a
              // low-friction, non-monetary ask rather than ending the
              // scroll on a sales pitch. Same TourProvider.tours the
              // standalone Tours screen (tours_list_screen.dart) reads —
              // no separate query here.
              SliverToBoxAdapter(
                child: Consumer<TourProvider>(
                  builder: (context, tourProv, _) {
                    final tours = tourProv.tours;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SectionHead(
                            title: 'TOURS & EXPERIENCES',
                            onSeeAll: () => context.go('/tours'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (tourProv.loading)
                          const FeaturedRowSkeleton()
                        else if (tourProv.hasError)
                          ErrorStateView(
                              onRetry: tourProv.refresh,
                              message: tourProv.error)
                        else if (tours.isEmpty)
                          const EmptyStateView(text: 'No tours available yet.')
                        else
                          SizedBox(
                            height: 290,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: tours.length,
                              itemBuilder: (ctx, i) =>
                                  _TourRailCard(tour: tours[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 20),

                    // Community row (static marketing)
                    _CommunityRow(),
                    const SizedBox(height: 20),

                    // Nearby gems heading
                    _SectionHead(
                      title: 'GEMS NEAR YOU',
                      onSeeAll: () => context.go('/listings'),
                    ),
                    const SizedBox(height: 12),

                    // Real, distance-sorted gems (best-effort location, own states)
                    const _NearbyGems(),

                    const SizedBox(height: 20),

                    // Banner
                    _BannerCard(),
                    const SizedBox(height: 100),
                  ]),
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
// HERO
// ─────────────────────────────────────────
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (decorative)
          const AppNetworkImage(
            url:
                'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80',
            fit: BoxFit.cover,
          ),
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppTheme.bg.withValues(alpha: 0.7),
                  AppTheme.bg,
                ],
                stops: const [0.3, 0.75, 1.0],
              ),
            ),
          ),
          // Orange tint
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.15),
                  Colors.transparent
                ],
              ),
            ),
          ),
          // Foreground — nav pinned to top, hero copy anchored to the bottom.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top nav
                  Row(
                    children: [
                      Text(
                        'Explor',
                        style: GoogleFonts.audiowide(
                          fontSize: 20,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'ife',
                        style: GoogleFonts.audiowide(
                          fontSize: 20,
                          color: AppTheme.primary,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      // Desktop-only: RefreshIndicator's pull gesture isn't
                      // discoverable with a mouse + scrollwheel the way it is
                      // on touch, so this gives desktop an explicit way to
                      // trigger the exact same GemProvider.refresh() call.
                      if (Breakpoints.isDesktop(context)) ...[
                        _CircleIconBtn(
                          icon: Icons.refresh,
                          semanticLabel: 'Refresh',
                          onTap: () => context.read<GemProvider>().refresh(),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _CircleIconBtn(
                        icon: Icons.notifications_outlined,
                        semanticLabel: 'Notifications',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No new notifications')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Semantics(
                        button: true,
                        label: 'Your profile',
                        child: GestureDetector(
                          onTap: () => context.go('/profile'),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.5),
                            ),
                            child: const ClipOval(
                              child: AppNetworkImage(
                                url: 'https://picsum.photos/seed/user1/80/80',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Hero copy
                  _LiveBadge(),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.bebasNeue(
                          fontSize: 48, height: 0.95, letterSpacing: 1),
                      children: const [
                        TextSpan(
                            text: 'THE LIFE\nYOU WERE\nMEANT TO\n',
                            style: TextStyle(color: Colors.white)),
                        TextSpan(
                            text: 'EXPLORE',
                            style: TextStyle(color: AppTheme.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Discover hidden trails, connect with fellow adventurers',
                    style: GoogleFonts.fredoka(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  // Start Exploring (DestinationBrowserSheet) retired in
                  // favor of the "EXPLORE IDEAS" rail below — see build()'s
                  // curated-collections section. That rail feeds the same
                  // Search Results / Destination Detail surface the search
                  // bar above already opens, instead of a separate modal.
                  Row(
                    children: [
                      _GhostIconBtn(
                        icon: Icons.explore_outlined,
                        semanticLabel: 'Open map',
                        onTap: () => context.go('/explore'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.2),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE ADVENTURE',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppTheme.primary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  const _CircleIconBtn(
      {required this.icon, required this.semanticLabel, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44, // min 44dp tap target
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _GhostIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  const _GhostIconBtn(
      {required this.icon, required this.onTap, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  // Third element is the route a tap lands on, or null for a purely
  // decorative pill — was null for all four before the Tours feature
  // existed (this whole Row had no GestureDetector/onTap anywhere). TRAILS
  // is the only one wired up so far: it's the one stat with a real,
  // dedicated destination now that the Tours list screen exists; the other
  // three (EXPLORERS/COUNTRIES/RATED) have no equivalent screen to land on.
  final _stats = const [
    ('12K+', 'TRAILS', '/tours'),
    ('84K', 'EXPLORERS', null),
    ('190+', 'COUNTRIES', null),
    ('4.9★', 'RATED', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
            horizontal: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: Row(
        children: _stats.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final route = s.$3;
          final cell = Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.lightCard,
              border: i < _stats.length - 1
                  ? const Border(right: BorderSide(color: AppTheme.lightBorder))
                  : null,
            ),
            child: Column(
              children: [
                Text(s.$1,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 20, color: AppTheme.primary)),
                Text(s.$2,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: AppTheme.lightMute,
                        letterSpacing: 0.5)),
              ],
            ),
          );
          return Expanded(
            child: route == null
                ? cell
                : Semantics(
                    button: true,
                    label: '${s.$1} ${s.$2}',
                    child: GestureDetector(
                        onTap: () => context.go(route), child: cell),
                  ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────
// SEARCH BAR
// ─────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search places, activities, and gems',
      child: GestureDetector(
        // Merged into ListingsScreen (/listings) — extra: true lands it
        // focused on the search field (Suggestions state) instead of the
        // default Browse view every other entry point opens.
        onTap: () => context.go('/listings', extra: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppTheme.lightMute, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search places, activities, gems…',
                  style: GoogleFonts.fredoka(
                      color: AppTheme.lightMute, fontSize: 14),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// CATEGORY PILLS
// ─────────────────────────────────────────
class _CategoryPills extends StatelessWidget {
  final List<({String label, IconData icon})> cats;
  final int selected;
  final ValueChanged<int> onSelect;
  const _CategoryPills(
      {required this.cats, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final isSelected = i == selected;
          final color = isSelected ? Colors.white : AppTheme.lightMute;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '${cats[i].label} category',
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.lightBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cats[i].icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(
                      cats[i].label,
                      style: GoogleFonts.fredoka(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
// SECTION HEADING
// ─────────────────────────────────────────
class _SectionHead extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHead({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: GoogleFonts.bebasNeue(
                fontSize: 28, letterSpacing: 0.5, color: AppTheme.lightInk)),
        const Spacer(),
        if (onSeeAll != null)
          Semantics(
            button: true,
            label: 'See all ${title.toLowerCase()}',
            child: GestureDetector(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'SEE ALL →',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: AppTheme.primary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// FEATURED GEM CARD (real Explorife gems)
// ─────────────────────────────────────────
class _FeaturedGemCard extends StatelessWidget {
  final Gem gem;
  final bool isTrending;
  final VoidCallback? onSave;
  const _FeaturedGemCard(
      {required this.gem, required this.isTrending, this.onSave});

  // Difficulty → colour + label, matched case-insensitively because stored
  // casing isn't guaranteed (e.g. 'Hard' vs 'hard'). Null when unset.
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
        return (color: AppTheme.textSecondary, label: d.toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _difficulty;
    final loc = gem.gemLocation;
    final hasLoc = loc != null && loc.isNotEmpty;
    final bestTime = gem.bestTimeToVisit;
    return PhotoInfoCard(
      imageUrl: gem.photoUrl ?? '',
      onTap: () => context.push('/gems/${gem.id}'),
      semanticLabel: hasLoc ? '${gem.gemName}, $loc' : gem.gemName,
      topLeft: isTrending
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department,
                      size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('TRENDING',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            )
          : null,
      // Save btn (not persisted yet → onSave shows a coming-soon hint)
      topRight: Semantics(
        button: true,
        label: 'Save ${gem.gemName}',
        child: GestureDetector(
          onTap: onSave,
          child: Container(
            width: 44, height: 44, // min tap target
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_outline,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag pill — same primary-tinted "tag" convention used on
          // _GemTrailRow's card below and the itinerary stop cards, at a
          // slightly higher alpha so it still pops against this card's dark
          // photo scrim (not the light page background the other cards sit
          // on).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${gem.emoji}  ${gem.displayCategory.toUpperCase()}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 9, color: AppTheme.primary, letterSpacing: 1.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(gem.gemName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bebasNeue(
                  fontSize: 22, color: Colors.white, height: 1)),
          if (hasLoc)
            Text(loc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fredoka(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
          const SizedBox(height: 8),
          Row(
            children: [
              if (diff != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: diff.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(diff.label,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: diff.color, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 8),
              ],
              if (bestTime != null && bestTime.isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 12, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(bestTime,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fredoka(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7))),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One card in Home's "EXPLORE IDEAS" rail — a real, curated collection
/// (curated_collections.dart), not a synthetic Gem, but built on the exact
/// same [PhotoInfoCard] shell _FeaturedGemCard uses above. Tapping navigates
/// straight into the same Search Results / Destination Detail screens Phase
/// 1 built; this card runs no query/retrieval logic of its own.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection});

  final CuratedCollection collection;

  /// Destination scope: resolves the city's real coordinates (same
  /// GeocodingService call every other city-tap flow in this app makes) and
  /// lands on Destination Detail directly — a single place, so there's no
  /// intermediate results list to show. Category scope: routes into
  /// ListingsScreen pre-filtered, the same deep link Home's category chips
  /// above already use.
  Future<void> _open(BuildContext context) async {
    final scope = collection.scope;
    if (!scope.isDestination) {
      context.go(scope.value == 'all' ? '/listings' : '/listings?category=${scope.value}');
      return;
    }
    final results = await GeocodingService().search(scope.value);
    if (!context.mounted) return;
    final place = results.isNotEmpty ? results.first : null;
    final label =
        (place != null && place.fullName.isNotEmpty) ? place.fullName : scope.value;
    final uri = Uri(path: '/destinations/explore', queryParameters: {
      'name': label,
      if (place?.lat != null) 'lat': '${place!.lat}',
      if (place?.lng != null) 'lng': '${place!.lng}',
    });
    if (context.mounted) context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return PhotoInfoCard(
      imageUrl: collection.coverImageUrl,
      onTap: () => _open(context),
      semanticLabel: collection.title,
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(collection.title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bebasNeue(
                  fontSize: 22, color: Colors.white, height: 1)),
          const SizedBox(height: 4),
          Text(collection.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fredoka(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
        ],
      ),
    );
  }
}

/// One card in Home's "TOURS & EXPERIENCES" rail — built on the same
/// [PhotoInfoCard] shell every other Home rail uses (_FeaturedGemCard,
/// _CollectionCard above), rather than reusing tours_list_screen.dart's own
/// [TourCard] verbatim: that card is sized for a GridView cell (relies on a
/// bounded-height parent via an internal Expanded) and isn't built on
/// PhotoInfoCard, so dropping it into a horizontal rail here would break
/// Home's one-shell-per-rail convention as well as need an extra sizing
/// wrapper. Same [Tour] data (TourProvider.tours) as the standalone
/// screen — no separate query, just a different display shell for the
/// same underlying tours.
class _TourRailCard extends StatelessWidget {
  const _TourRailCard({required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    return PhotoInfoCard(
      imageUrl: tour.coverPhoto ?? '',
      onTap: () => context.push('/tours/${tour.id}'),
      semanticLabel: tour.name,
      // Never automatic — see Tour.isCurated's own doc comment for why
      // this is the ONLY thing that ever shows this badge.
      topLeft: tour.isCurated
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tour.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bebasNeue(
                  fontSize: 20, color: Colors.white, height: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (tour.durationLabel != null &&
                  tour.durationLabel!.isNotEmpty) ...[
                Icon(Icons.schedule,
                    size: 12, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(tour.durationLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fredoka(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7))),
                ),
              ],
              if (tour.pickupIncluded) ...[
                const SizedBox(width: 4),
                Icon(Icons.directions_car_filled_outlined,
                    size: 12, color: Colors.white.withValues(alpha: 0.7)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'From ',
                  style: GoogleFonts.fredoka(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.65))),
              TextSpan(
                  text: '${tour.currency} ${tour.priceFrom}',
                  style: GoogleFonts.fredoka(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// COMMUNITY ROW
// ─────────────────────────────────────────
class _CommunityRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final avatars = ['av1', 'av2', 'av3'];
    return Row(
      children: [
        // Avatar cluster — the "+84K" badge is the 4th overlapping member.
        SizedBox(
          width: 36.0 + avatars.length * 22.0,
          height: 36,
          child: Stack(
            children: [
              ...avatars.asMap().entries.map((e) => Positioned(
                    left: e.key * 22.0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.lightSurface, width: 2),
                      ),
                      child: ClipOval(
                        child: AppNetworkImage(
                          url: 'https://picsum.photos/seed/${e.value}/80/80',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )),
              Positioned(
                left: avatars.length * 22.0,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.lightSurface, width: 2),
                  ),
                  child: Center(
                    child: Text('+84K',
                        style: GoogleFonts.fredoka(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.fredoka(
                  fontSize: 12, color: AppTheme.lightMute, height: 1.5),
              children: const [
                TextSpan(
                    text: '84,000+ adventurers ',
                    style: TextStyle(
                        color: AppTheme.lightInk, fontWeight: FontWeight.w600)),
                TextSpan(text: 'are exploring right now. Join the tribe.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// GEMS NEAR YOU  (real, distance-sorted gems via GemProvider)
// ─────────────────────────────────────────
class _NearbyGems extends StatefulWidget {
  const _NearbyGems();

  @override
  State<_NearbyGems> createState() => _NearbyGemsState();
}

class _NearbyGemsState extends State<_NearbyGems> {
  // Best-effort device location. Null until (and unless) it resolves — the
  // list then falls back to newest gems, so the section never waits on a prompt.
  double? _lat, _lng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveLocation());
  }

  Future<void> _resolveLocation() async {
    // Best-effort only: never block first paint, and on ANY failure/denial stay
    // on the newest-gems fallback. Note: the browser Geolocation API only works
    // in a secure context (HTTPS or localhost); on a plain-HTTP preview it's
    // silently denied — expected, not a bug.
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      // Stay silent — the fallback list already covers this.
    }
  }

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    if (gem.loading) return const TrailListSkeleton();
    if (gem.error != null) {
      return ErrorStateView(onRetry: gem.refresh, message: gem.error);
    }
    final list = gem.nearbyGems(_lat, _lng).take(3).toList();
    if (list.isEmpty) {
      return const EmptyStateView(text: 'No gems nearby yet.');
    }
    return Column(
      children: list
          .map((g) => _GemTrailRow(
                gem: g,
                distanceKm: gem.distanceKmFrom(_lat, _lng, g),
              ))
          .toList(),
    );
  }
}

class _GemTrailRow extends StatelessWidget {
  final Gem gem;
  final double? distanceKm;
  const _GemTrailRow({required this.gem, this.distanceKm});

  /// Difficulty pill colour + label by level; null hides the pill entirely.
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
      explicitChildNodes: true,
      child: GestureDetector(
        onTap: () => context.push('/gems/${gem.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              AppNetworkImage(
                url: gem.photoUrl ?? '',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gem.gemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fredoka(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.lightInk)),
                    if (gem.gemLocation != null &&
                        gem.gemLocation!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 12, color: AppTheme.lightMute),
                        Expanded(
                          child: Text(gem.gemLocation!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.fredoka(
                                  fontSize: 11, color: AppTheme.lightMute)),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(gem.displayCategory.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppTheme.primary,
                              letterSpacing: 0.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (diff != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: diff.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(diff.label,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: diff.color,
                              letterSpacing: 0.5)),
                    ),
                  if (distanceKm != null) ...[
                    const SizedBox(height: 6),
                    Text('${distanceKm!.toStringAsFixed(1)} km',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// BANNER CARD
// ─────────────────────────────────────────
class _BannerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 152,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const AppNetworkImage(
              url:
                  'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=800&q=80',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.backpack,
                          size: 12, color: AppTheme.primary),
                      const SizedBox(width: 5),
                      Text('COMMUNITY',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppTheme.primary,
                              letterSpacing: 2)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('JOIN THE\nTRIBE',
                      style: GoogleFonts.bebasNeue(
                          fontSize: 24, color: Colors.white, height: 1)),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: 'Connect now',
                    child: GestureDetector(
                      onTap: () => context.go('/stories'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Connect Now',
                            style: GoogleFonts.fredoka(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

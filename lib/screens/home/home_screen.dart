import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/layout/app_spacing.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/curated_collection_provider.dart';
import '../../providers/gem_provider.dart';
import '../../providers/tour_provider.dart';
import '../../models/curated_collection.dart';
import '../../models/gem.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/state_views.dart';
import '../../widgets/tours/tour_experience_card.dart';
import 'widgets/hero_media_background.dart';

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
    final tier = Breakpoints.tierOf(context);
    // MaxWidthCenter's own cap (900/640) is tuned for the narrow single-
    // column screens that already use it (Profile tabs, etc.) — Home's
    // grids need a much wider cap that also kicks in earlier, at the new
    // tablet tier (768), so this computes its own constraint instead of
    // reusing that shared helper.
    final maxContentWidth = tier == ScreenTier.phone ? double.infinity : 1280.0;
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.lightCard,
          onRefresh: () => context.read<GemProvider>().refresh(),
          child: CustomScrollView(
            // alwaysScrollable so pull-to-refresh works even when content is short
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── HERO (+ stats bar merged into its own bottom edge) ──
              // Both the hero copy card and the stats strip now live inside
              // one rounded, inset media card (see _Hero) — matching the
              // prototype's single "hero" unit instead of the previous
              // flush-bleed hero with a separate light stats bar stacked
              // below/overlapping it.
              const SliverToBoxAdapter(child: _Hero()),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.sectionGap)),

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
                    const SizedBox(height: AppSpacing.sectionGap),
                  ]),
                ),
              ),

              // ── EXPLORE IDEAS (curated collections rail) ──
              // Replaces Start Exploring / DestinationBrowserSheet. Backed
              // by CuratedCollectionProvider (public.curated_collections)
              // as of 2026-09-18 — was a hardcoded static Dart list before
              // that. Every card navigates straight into Search Results or
              // Destination Detail, the same screens the search bar above
              // already opens. See _CollectionCard.
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _SectionHead(title: 'EXPLORE IDEAS'),
                ),
              ),
              SliverToBoxAdapter(
                child: Consumer<CuratedCollectionProvider>(
                  builder: (context, collectionProv, _) {
                    final collections = collectionProv.collections;
                    if (collectionProv.loading) {
                      return const FeaturedRowSkeleton();
                    }
                    if (collectionProv.hasError) {
                      return ErrorStateView(
                          onRetry: collectionProv.refresh,
                          message: collectionProv.error);
                    }
                    if (collections.isEmpty) {
                      return const EmptyStateView(
                          text: 'No ideas available yet.');
                    }
                    return _RailOrGrid(
                      itemCount: collections.length,
                      itemBuilder: (ctx, i) => _CollectionCard(
                        collection: collections[i],
                        onSave: () => _comingSoonSave(ctx),
                      ),
                    );
                  },
                ),
              ),
              const SliverPadding(
                  padding: EdgeInsets.only(top: AppSpacing.sectionGap)),

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
                        const SizedBox(height: AppSpacing.headerGap),
                        if (gem.loading)
                          const FeaturedRowSkeleton()
                        else if (gem.hasError)
                          ErrorStateView(
                              onRetry: gem.refresh, message: gem.error)
                        else if (featuredGems.isEmpty)
                          const EmptyStateView(text: 'No featured gems yet.')
                        else
                          _RailOrGrid(
                            itemCount: featuredGems.length,
                            itemBuilder: (ctx, i) => _FeaturedGemCard(
                              gem: featuredGems[i],
                              isTrending: gem.isTrending(featuredGems[i]),
                              onSave: () => _comingSoonSave(ctx),
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
                        const SizedBox(height: AppSpacing.headerGap),
                        if (tourProv.loading)
                          const FeaturedRowSkeleton()
                        else if (tourProv.hasError)
                          ErrorStateView(
                              onRetry: tourProv.refresh,
                              message: tourProv.error)
                        else if (tours.isEmpty)
                          const EmptyStateView(text: 'No tours available yet.')
                        else
                          // A dedicated, taller rail (not _RailOrGrid's
                          // shared fixed 290px height) — each card here is
                          // a full mini tour-detail view (hero, tabs,
                          // booking pills, footer CTA), not the compact
                          // summary shell every other Home rail uses, so it
                          // needs its own height budget. See
                          // TourExperienceCard's own doc comment for why.
                          SizedBox(
                            height: TourExperienceCard.height,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: tours.length,
                              itemBuilder: (ctx, i) =>
                                  TourExperienceCard(tour: tours[i]),
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
                    const SizedBox(height: AppSpacing.sectionGap),

                    // Community row (static marketing)
                    _CommunityRow(),
                    const SizedBox(height: AppSpacing.sectionGap),

                    // Nearby gems heading
                    _SectionHead(
                      title: 'GEMS NEAR YOU',
                      onSeeAll: () => context.go('/listings'),
                    ),
                    const SizedBox(height: AppSpacing.headerGap),

                    // Real, distance-sorted gems (best-effort location, own states)
                    _NearbyGems(tier: tier),

                    const SizedBox(height: AppSpacing.sectionGap),

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
      ),
    );
  }
}

// ─────────────────────────────────────────
// HERO
// ─────────────────────────────────────────
/// Hero — matches the prototype's single rounded, inset "hero" unit: a
/// video/poster media card (unchanged from before, see
/// widgets/hero_media_background.dart) clipped to rounded corners and inset
/// from the screen edges (rather than the old full-bleed edge-to-edge
/// treatment), with a glass copy card anchored top-left (see
/// [_HeroGlassCard]) and a dark glass stats strip pinned to its own bottom
/// edge (see [_HeroStatsBar]) — both now part of the same rounded card
/// instead of a separate light stats bar stacked below/overlapping it.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    // Tablet/desktop already get logo + hamburger + search + avatar from
    // AppShell's sticky top bar (see _TopBar in app_shell.dart) — repeating
    // that whole row here too would be the exact "two menu/nav headers on
    // screen at once" duplication this rebuild was asked to avoid, so phone
    // is the only tier that renders its own top nav row inside the hero.
    final isPhone = Breakpoints.tierOf(context) == ScreenTier.phone;
    final outerPad = isPhone ? 16.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(outerPad, 12, outerPad, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isPhone ? 16 : 24),
        child: SizedBox(
          height: 520,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background (decorative) — a looping video on Web (autoplay/
              // muted, falling back to the static poster for reduced-motion/
              // data-saver/slow connections or any playback error), and the
              // same static poster image on mobile.
              const HeroMediaBackground(),
              // Darken the top/bottom edges slightly so the glass card and
              // stats bar stay legible regardless of what's playing behind
              // them — same intent as the prototype's `.hero::after`.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                    ],
                    stops: const [0.0, 0.28, 0.62, 1.0],
                  ),
                ),
              ),
              // Foreground — nav pinned to top, hero copy card anchored
              // top-left.
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      isPhone ? 16 : 32, isPhone ? 12 : 28, isPhone ? 16 : 32, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isPhone)
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
                            _CircleIconBtn(
                              icon: Icons.notifications_outlined,
                              semanticLabel: 'Notifications',
                              onTap: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('No new notifications')),
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
                                        color: Colors.white
                                            .withValues(alpha: 0.25),
                                        width: 1.5),
                                  ),
                                  child: const ClipOval(
                                    child: AppNetworkImage(
                                      url:
                                          'https://picsum.photos/seed/user1/80/80',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        // Tablet/desktop: RefreshIndicator's pull gesture
                        // isn't discoverable with a mouse + scrollwheel the
                        // way it is on touch, so this gives them an explicit
                        // way to trigger the exact same
                        // GemProvider.refresh() call — the one piece of the
                        // old top row worth keeping once the rest moved to
                        // AppShell's top bar.
                        Align(
                          alignment: Alignment.topRight,
                          child: _CircleIconBtn(
                            icon: Icons.refresh,
                            semanticLabel: 'Refresh',
                            onTap: () => context.read<GemProvider>().refresh(),
                          ),
                        ),
                      SizedBox(height: isPhone ? 20 : 28),
                      _HeroGlassCard(isPhone: isPhone),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _HeroStatsBar(isPhone: isPhone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The translucent dark "glass" copy card anchored top-left inside the hero
/// — headline + subtext + CTA. [CuratedCollection]'s own "no fake data"
/// principle doesn't apply here (this copy is static marketing, not a data
/// card), so it's just a direct port of the prototype's `.hero-card`.
class _HeroGlassCard extends StatelessWidget {
  const _HeroGlassCard({required this.isPhone});
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: BoxConstraints(maxWidth: isPhone ? double.infinity : 460),
          padding: EdgeInsets.all(isPhone ? 22 : 36),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  style: GoogleFonts.instrumentSerif(
                    fontSize: isPhone ? 30 : 44,
                    height: 1.08,
                    color: Colors.white,
                  ),
                  children: const [
                    TextSpan(text: 'The life you were\nmeant to '),
                    TextSpan(
                        text: 'explore',
                        style: TextStyle(color: AppTheme.primary)),
                  ],
                ),
              ),
              SizedBox(height: isPhone ? 12 : 16),
              Text(
                'Discover hidden trails, connect with fellow adventurers.',
                style: GoogleFonts.fredoka(
                  fontSize: isPhone ? 12.5 : 14,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              SizedBox(height: isPhone ? 18 : 26),
              // The old standalone "Start Exploring" modal
              // (DestinationBrowserSheet) was retired in favor of the
              // "EXPLORE IDEAS" rail below — see build()'s curated-
              // collections section; that rail (and this CTA) both feed the
              // same Search Results / Destination Detail surface, not a
              // separate flow. One labeled pill at every tier now (matching
              // the prototype), replacing the old phone-only icon button.
              _StartExploringPill(onTap: () => context.go('/explore')),
            ],
          ),
        ),
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

/// The hero's single CTA pill — used across all tiers now that [_Hero] is
/// one unified rounded card (previously phone got an icon-only ghost button
/// and only tablet/desktop got this labeled pill; see git history).
class _StartExploringPill extends StatelessWidget {
  const _StartExploringPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start exploring',
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(27),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(27),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Start Exploring',
                    style: GoogleFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// STATS BAR (dark glass strip pinned to the hero's own bottom edge —
// matches the prototype's `.stats-bar` grid of blurred `.stat-item` cells)
// ─────────────────────────────────────────
class _HeroStatsBar extends StatelessWidget {
  const _HeroStatsBar({required this.isPhone});
  final bool isPhone;

  // Third element is the route a tap lands on, or null for a purely
  // decorative cell — was null for all four before the Tours feature
  // existed. TRAILS is the only one wired up so far: it's the one stat with
  // a real, dedicated destination now that the Tours list screen exists;
  // the other three (EXPLORERS/COUNTRIES/RATED) have no equivalent screen
  // to land on.
  static const _stats = [
    ('12K+', 'TRAILS', '/tours'),
    ('84K', 'EXPLORERS', null),
    ('190+', 'COUNTRIES', null),
    ('4.9★', 'RATED', null),
  ];

  Widget _cell(BuildContext context, int i) {
    final s = _stats[i];
    final route = s.$3;
    final content = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: const Color(0xFF111827).withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.$1,
                  style: GoogleFonts.fredoka(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(s.$2,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.65),
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
    return Expanded(
      child: route == null
          ? content
          : Semantics(
              button: true,
              label: '${s.$1} ${s.$2}',
              child:
                  GestureDetector(onTap: () => context.go(route), child: content),
            ),
    );
  }

  // 1px hairline seams between cells — Flutter equivalent of the
  // prototype's `.stats-bar { gap: 1px; background: rgba(255,255,255,.25) }`
  // grid trick: a translucent-white sliver peeking through between the
  // opaque glass cells.
  static const _hairlineV =
      SizedBox(width: 1, child: ColoredBox(color: Color(0x40FFFFFF)));
  static const _hairlineH =
      SizedBox(height: 1, child: ColoredBox(color: Color(0x40FFFFFF)));

  @override
  Widget build(BuildContext context) {
    if (isPhone) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [_cell(context, 0), _hairlineV, _cell(context, 1)]),
          _hairlineH,
          Row(children: [_cell(context, 2), _hairlineV, _cell(context, 3)]),
        ],
      );
    }
    return Row(
      children: [
        _cell(context, 0),
        _hairlineV,
        _cell(context, 1),
        _hairlineV,
        _cell(context, 2),
        _hairlineV,
        _cell(context, 3),
      ],
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
      label: 'Explore by category or destination',
      child: GestureDetector(
        // Merged into ListingsScreen (/listings) — extra: true lands it
        // focused on the search field (Suggestions state) instead of the
        // default Browse view every other entry point opens.
        onTap: () => context.go('/listings', extra: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppTheme.lightMute, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Explore by Category or Destination...',
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
          // Home never tracks a persistent selection (see the caller's
          // comment — a tap is a one-shot shortcut into Listings, not a
          // filter reflected back here), but the prototype's "All" chip is
          // always drawn active/dark as the default resting state. Reproduce
          // that purely presentational default — index 0 with no real
          // selection — without adding real selection-tracking state.
          final isDefaultAll = selected == -1 && i == 0;
          final color =
              isSelected || isDefaultAll ? Colors.white : AppTheme.lightMute;
          final fill = isSelected
              ? AppTheme.primary
              : isDefaultAll
                  ? const Color(0xFF111827)
                  : AppTheme.lightCard;
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
                  color: fill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: fill),
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
/// Horizontally-scrollable rail of fixed-width cards, used by every "row of
/// cards" section on Home (Explore Ideas/Featured/Tours) at every screen
/// tier — cards are a fixed width (_IdeaStyleCard.width), so a wider
/// viewport simply reveals more cards in the same scrolling rail instead of
/// wrapping into a capped, non-scrolling grid.
class _RailOrGrid extends StatelessWidget {
  const _RailOrGrid({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Matches every current rail's own fixed card height (Explore Ideas/
  /// Featured/Tours all used 290 before this helper existed).
  static const double _railHeight = 290;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _railHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

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

/// Shared "idea card" shell for every Home rail (Explore Ideas, Featured,
/// Tours & Experiences): dark card, photo up top with a frosted save
/// button, an optional top-left badge, and an optional photo-caption strip
/// on the photo's own bottom edge, then an info block below (title,
/// 2-line subtitle, a neutral tag pill, an optional card-specific "meta"
/// row for real secondary data), a divider, then a solid-button footer.
/// Only the slot *content* differs per rail — the shape never does, which
/// is the whole point of pulling it out: previously Featured/Tours used a
/// different shell ([PhotoInfoCard]) than Explore Ideas, so the three
/// rails didn't visually match.
///
/// Dark theme + photo-caption strip + button-style footer CTA (2026-09-08)
/// replaced this shell's original light-card look, matching a design
/// reference the product owner shared. Two elements in that reference had
/// no real backing data and were deliberately NOT reproduced rather than
/// faked: a star rating badge (this app has no rating field anywhere — see
/// Tour's own doc comment for why) and a footer "N experiences" counter (no
/// such count is tracked for any rail's content). [photoCaption] is wired
/// to real data where it exists (Gem.photoCaptions) and left null
/// everywhere else, rather than inventing caption text.
class _IdeaStyleCard extends StatefulWidget {
  const _IdeaStyleCard({
    required this.imageUrl,
    required this.onTap,
    required this.semanticLabel,
    required this.title,
    required this.tagLabel,
    required this.footerLeft,
    required this.footerCta,
    this.subtitle,
    this.topLeftBadge,
    this.photoCaption,
    this.onSave,
    this.saveSemanticLabel,
    this.metaRow,
  });

  final String imageUrl;
  final VoidCallback onTap;
  final String semanticLabel;
  final String title;
  final String? subtitle;
  final String tagLabel;
  final Widget? topLeftBadge;

  /// Real per-photo caption text (e.g. Gem.captionFor), shown in a strip
  /// along the photo's own bottom edge. Null omits the strip entirely —
  /// never filled with invented text for a card type with no such field.
  final String? photoCaption;
  final VoidCallback? onSave;
  final String? saveSemanticLabel;
  final Widget? metaRow;
  final Widget footerLeft;
  final String footerCta;

  // Fixed shape every Home rail card shares.
  static const double width = 225;
  static const double height = 290;

  @override
  State<_IdeaStyleCard> createState() => _IdeaStyleCardState();
}

class _IdeaStyleCardState extends State<_IdeaStyleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _IdeaStyleCard.width,
            height: _IdeaStyleCard.height,
            margin: const EdgeInsets.only(right: 14),
            transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
            decoration: BoxDecoration(
              // Matches the app's existing "dark glass" surface colour
              // (_HeroGlassCard/_HeroStatsBar) rather than pure black, so
              // this shell reads as the same design language elsewhere on
              // Home instead of a one-off.
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.32 : 0.18),
                  blurRadius: _hovered ? 24 : 8,
                  offset: Offset(0, _hovered ? 12 : 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── photo + optional badge + frosted save button ──
                  Expanded(
                    flex: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          scale: _hovered ? 1.08 : 1.0,
                          child: AppNetworkImage(
                              url: widget.imageUrl, fit: BoxFit.cover),
                        ),
                        if (widget.topLeftBadge != null)
                          Positioned(
                              top: 8, left: 8, child: widget.topLeftBadge!),
                        if (widget.onSave != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Semantics(
                              button: true,
                              label: widget.saveSemanticLabel ?? 'Save',
                              child: GestureDetector(
                                onTap: widget.onSave,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.favorite_border,
                                        color: Colors.white, size: 15),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Real photo caption only (see photoCaption's own
                        // doc comment) — never rendered for a card type
                        // with no such field.
                        if (widget.photoCaption != null &&
                            widget.photoCaption!.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              color: Colors.black.withValues(alpha: 0.45),
                              child: Text(widget.photoCaption!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.fredoka(
                                      fontSize: 10.5, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── title / subtitle / tag / meta / divider / link footer ──
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.bebasNeue(
                                      fontSize: 18,
                                      color: Colors.white,
                                      height: 1.1,
                                      letterSpacing: 0.3)),
                              const SizedBox(height: 3),
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty) ...[
                                Text(widget.subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.fredoka(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.65),
                                        height: 1.25)),
                                const SizedBox(height: 3),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.14)),
                                ),
                                child: Text(widget.tagLabel,
                                    style: GoogleFonts.fredoka(
                                        fontSize: 10,
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontWeight: FontWeight.w500)),
                              ),
                              if (widget.metaRow != null) ...[
                                const SizedBox(height: 4),
                                widget.metaRow!,
                              ],
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Divider(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.12)),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(child: widget.footerLeft),
                                  const SizedBox(width: 6),
                                  // Solid button (was a plain text link) —
                                  // matches the referenced design's white
                                  // pill CTA; text content is unchanged real
                                  // per-card copy ("View →" / "Explore →" /
                                  // "Book →").
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(widget.footerCta,
                                        style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            color: const Color(0xFF111827),
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
        return (color: const Color(0xFF2ECC71), label: 'Easy');
      case 'moderate':
      case 'mod':
        return (color: const Color(0xFFE8A83C), label: 'Moderate');
      case 'hard':
        return (color: AppTheme.primary, label: 'Hard');
      default:
        return (color: AppTheme.lightMute, label: d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _difficulty;
    final loc = gem.gemLocation;
    final hasLoc = loc != null && loc.isNotEmpty;
    final desc = gem.description;
    final subtitle = (desc != null && desc.isNotEmpty)
        ? desc
        : (hasLoc ? loc : gem.tagline);
    final bestTime = gem.bestTimeToVisit;
    // Real per-photo caption when one was actually written for this gem's
    // cover photo (see Gem.photoCaptions's own doc comment) — most gems
    // have none, in which case the strip is simply omitted (photoCaption's
    // own doc comment on _IdeaStyleCard).
    final caption = gem.photoUrl != null ? gem.captionFor(gem.photoUrl!) : null;

    return _IdeaStyleCard(
      imageUrl: gem.photoUrl ?? '',
      onTap: () => context.push('/gems/${gem.id}'),
      semanticLabel: hasLoc ? '${gem.gemName}, $loc' : gem.gemName,
      title: gem.gemName,
      subtitle: subtitle,
      tagLabel: '${gem.emoji} ${gem.displayCategory}',
      photoCaption: caption,
      // Save btn (not persisted yet → onSave shows a coming-soon hint)
      onSave: onSave,
      saveSemanticLabel: 'Save ${gem.gemName}',
      topLeftBadge: isTrending
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
      metaRow: (bestTime != null && bestTime.isNotEmpty)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 12, color: AppTheme.lightMute),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(bestTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fredoka(
                          fontSize: 10.5, color: AppTheme.lightMute)),
                ),
              ],
            )
          : null,
      footerLeft: diff != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: diff.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(diff.label,
                    style: GoogleFonts.fredoka(
                        fontSize: 10.5,
                        color: diff.color,
                        fontWeight: FontWeight.w600)),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_outlined, size: 13, color: AppTheme.lightMute),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(hasLoc ? loc : 'Gem',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fredoka(
                          fontSize: 10.5, color: AppTheme.lightMute)),
                ),
              ],
            ),
      footerCta: 'View →',
    );
  }
}

/// One card in Home's "EXPLORE IDEAS" rail — a real, curated collection
/// (public.curated_collections), not a synthetic Gem. No rating/price exists
/// on [CuratedCollection] (it's editorial, not a bookable listing), so the
/// tag row and footer show the collection's real scope instead of
/// inventing numbers. Built on the shared [_IdeaStyleCard] shell — see its
/// doc comment for why Featured/Tours below now use the same shell too.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    this.onSave,
  });

  final CuratedCollection collection;
  final VoidCallback? onSave;

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

  /// Real count of gems that fall inside this collection's scope — never a
  /// fabricated number. Category scope is an exact match against
  /// [GemProvider.search]'s own category filter; destination scope reuses
  /// the exact same fuzzy substring match against `gemLocation` that
  /// [DestinationLandingScreen] already performs for the same city (no
  /// separate/stricter matcher invented just for this count, so the number
  /// shown here always agrees with what that screen would actually list).
  int _experienceCount(GemProvider gems, CollectionScope scope) {
    return scope.isDestination
        ? gems.search(query: scope.value).length
        : gems.search(category: scope.value).length;
  }

  @override
  Widget build(BuildContext context) {
    final scope = collection.scope;
    final tagLabel = scope.value == 'all'
        ? 'All'
        : scope.value[0].toUpperCase() + scope.value.substring(1);
    final count = _experienceCount(context.watch<GemProvider>(), scope);
    final rating = collection.rating;
    final bestTime = collection.bestTimeToVisit;

    return _IdeaStyleCard(
      imageUrl: collection.coverImageUrl,
      onTap: () => _open(context),
      semanticLabel: collection.title,
      title: collection.title,
      subtitle: collection.subtitle,
      tagLabel: tagLabel,
      onSave: onSave,
      saveSemanticLabel: 'Save ${collection.title}',
      // Curator-assigned (see CuratedCollection.rating's own doc comment) —
      // not a computed/aggregated score. Only ever set for destination
      // scope, so this is simply absent for category collections.
      topLeftBadge: rating != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC542)),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1),
                      style: GoogleFonts.fredoka(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            )
          : null,
      // Curator-written seasonal advice (see CuratedCollection.bestTimeToVisit)
      // — same slot/style _FeaturedGemCard uses for the real
      // gem.bestTimeToVisit field, so this reads identically to that one.
      metaRow: (bestTime != null && bestTime.isNotEmpty)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 12, color: AppTheme.lightMute),
                const SizedBox(width: 4),
                Text('Best time: $bestTime',
                    style: GoogleFonts.fredoka(fontSize: 10.5, color: AppTheme.lightMute)),
              ],
            )
          : null,
      footerLeft: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            scope.isDestination
                ? Icons.place_outlined
                : Icons.local_fire_department_outlined,
            size: 13,
            color: AppTheme.lightMute,
          ),
          const SizedBox(width: 4),
          Text(count == 1 ? '1 experience' : '$count experiences',
              style: GoogleFonts.fredoka(fontSize: 10.5, color: AppTheme.lightMute)),
        ],
      ),
      footerCta: 'Explore →',
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
  const _NearbyGems({required this.tier});

  final ScreenTier tier;

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
    // Phone shows exactly 3 stacked rows (unchanged). Tablet/desktop's grid
    // has 2 columns, so 4 fills it evenly (2 rows of 2) instead of leaving
    // an awkward single trailing card on its own row.
    final count = widget.tier == ScreenTier.phone ? 3 : 4;
    final list = gem.nearbyGems(_lat, _lng).take(count).toList();
    if (list.isEmpty) {
      return const EmptyStateView(text: 'No gems nearby yet.');
    }
    if (widget.tier == ScreenTier.phone) {
      return Column(
        children: list
            .map((g) => _GemTrailRow(
                  gem: g,
                  distanceKm: gem.distanceKmFrom(_lat, _lng, g),
                ))
            .toList(),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 100,
      ),
      itemBuilder: (ctx, i) => _GemTrailRow(
        gem: list[i],
        distanceKm: gem.distanceKmFrom(_lat, _lng, list[i]),
        margin: EdgeInsets.zero,
      ),
    );
  }
}

class _GemTrailRow extends StatelessWidget {
  final Gem gem;
  final double? distanceKm;
  final EdgeInsets margin;
  const _GemTrailRow(
      {required this.gem,
      this.distanceKm,
      this.margin = const EdgeInsets.only(bottom: 10)});

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
          margin: margin,
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

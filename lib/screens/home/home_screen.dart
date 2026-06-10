import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/destination_provider.dart';
import '../../models/destination.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCat = 0;
  final List<String> _cats = ['🌍 All', '🏔️ Hiking', '🏖️ Beach', '🧗 Climbing', '🌿 Jungle', '🏜️ Desert', '❄️ Arctic'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DestinationProvider>();
    final featured = provider.featured;
    final all = provider.destinations;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          // ── HERO ──
          SliverToBoxAdapter(child: _Hero()),

          // ── STATS BAR ──
          SliverToBoxAdapter(child: _StatsBar()),

          // ── BODY ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),

                // Search bar
                _SearchBar(),
                const SizedBox(height: 16),

                // Categories
                _CategoryPills(
                  cats: _cats,
                  selected: _selectedCat,
                  onSelect: (i) => setState(() => _selectedCat = i),
                ),
                const SizedBox(height: 20),

                // Featured heading
                _SectionHead(
                  title: 'FEATURED',
                  onSeeAll: () => context.go('/listings'),
                ),
                const SizedBox(height: 12),
              ]),
            ),
          ),

          // Featured horizontal scroll (edge-to-edge)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 290,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: featured.length,
                itemBuilder: (ctx, i) => _FeaturedCard(destination: featured[i]),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),

                // Community row
                _CommunityRow(),
                const SizedBox(height: 20),

                // Trails heading
                _SectionHead(title: 'TRAILS NEAR YOU', onSeeAll: () => context.go('/listings')),
                const SizedBox(height: 12),

                // Trail cards
                ...all.take(3).map((d) => _TrailCard(destination: d)),
                const SizedBox(height: 20),

                // Banner
                _BannerCard(),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
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
          // Background image
          Image.network(
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
                  AppTheme.bg.withOpacity(0.7),
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
                colors: [AppTheme.primary.withOpacity(0.15), Colors.transparent],
              ),
            ),
          ),
          // Top nav
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Explor',
                    style: GoogleFonts.audiowide(
                      fontSize: 20, color: Colors.white, letterSpacing: 1,
                    ),
                  ),
                  Text(
                    'ife',
                    style: GoogleFonts.audiowide(
                      fontSize: 20, color: AppTheme.primary, letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  _CircleIconBtn(icon: Icons.notifications_outlined),
                  const SizedBox(width: 10),
                  ClipOval(
                    child: Image.network(
                      'https://picsum.photos/seed/user1/80/80',
                      width: 38, height: 38, fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Hero text
          Positioned(
            bottom: 24, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LiveBadge(),
                const SizedBox(height: 10),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.bebasNeue(fontSize: 52, height: 0.95, letterSpacing: 1),
                    children: [
                      const TextSpan(text: 'THE LIFE\nYOU WERE\nMEANT TO\n', style: TextStyle(color: Colors.white)),
                      TextSpan(text: 'EXPLORE', style: TextStyle(color: AppTheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Discover hidden trails, connect with fellow adventurers',
                  style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withOpacity(0.75), height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.go('/listings'),
                        child: const Text('Start Exploring'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GhostIconBtn(icon: Icons.explore_outlined, onTap: () => context.go('/explore')),
                  ],
                ),
              ],
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
        color: AppTheme.primary.withOpacity(0.2),
        border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE ADVENTURE',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: AppTheme.primary, letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  const _CircleIconBtn({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class _GhostIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GhostIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final _stats = const [
    ('12K+', 'TRAILS'), ('84K', 'EXPLORERS'), ('190+', 'COUNTRIES'), ('4.9★', 'RATED'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: _stats.asMap().entries.map((e) {
          final i = e.key; final s = e.value;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                border: i < _stats.length - 1
                    ? Border(right: BorderSide(color: AppTheme.divider))
                    : null,
              ),
              child: Column(
                children: [
                  Text(s.$1, style: GoogleFonts.bebasNeue(fontSize: 20, color: AppTheme.primary)),
                  Text(s.$2, style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                ],
              ),
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
    return GestureDetector(
      onTap: () => context.go('/search'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search destinations, trails...',
                style: GoogleFonts.dmSans(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ),
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune, color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// CATEGORY PILLS
// ─────────────────────────────────────────
class _CategoryPills extends StatelessWidget {
  final List<String> cats;
  final int selected;
  final ValueChanged<int> onSelect;
  const _CategoryPills({required this.cats, required this.selected, required this.onSelect});

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
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : AppTheme.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : AppTheme.divider,
                ),
              ),
              child: Text(
                cats[i],
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
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
        Text(title, style: GoogleFonts.bebasNeue(fontSize: 28, letterSpacing: 0.5, color: AppTheme.textPrimary)),
        const Spacer(),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'SEE ALL →',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.primary),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// FEATURED CARD
// ─────────────────────────────────────────
class _FeaturedCard extends StatelessWidget {
  final Destination destination;
  const _FeaturedCard({required this.destination});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/listings/${destination.id}'),
      child: Container(
        width: 225,
        margin: const EdgeInsets.only(right: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(destination.imageUrl, fit: BoxFit.cover),
              // Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
              // Trending badge
              if (destination.rating >= 4.9)
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('🔥 TRENDING',
                        style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              // Save btn
              Positioned(
                top: 12, right: 12,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bookmark_outline, color: Colors.white, size: 16),
                ),
              ),
              // Info
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.category.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.primary, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 4),
                      Text(destination.name.toUpperCase(),
                          style: GoogleFonts.bebasNeue(fontSize: 22, color: Colors.white, height: 1)),
                      Text(destination.country,
                          style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white.withOpacity(0.65))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Row(children: [
                            const Icon(Icons.star, size: 12, color: Colors.amber),
                            const SizedBox(width: 3),
                            Text('${destination.rating}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                            Text(' (${destination.reviewCount})',
                                style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                          ]),
                          const Spacer(),
                          Text('\$${destination.pricePerNight.toInt()}/n',
                              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.primary)),
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
        SizedBox(
          width: 80, height: 36,
          child: Stack(
            children: avatars.asMap().entries.map((e) => Positioned(
              left: e.key * 22.0,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.bg, width: 2),
                ),
                child: ClipOval(
                  child: Image.network(
                    'https://picsum.photos/seed/${e.value}/80/80',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
        Container(
          width: 36, height: 36,
          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
          child: Center(
            child: Text('+84K', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
              children: const [
                TextSpan(text: '84,000+ adventurers ', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
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
// TRAIL CARD
// ─────────────────────────────────────────
class _TrailCard extends StatelessWidget {
  final Destination destination;
  const _TrailCard({required this.destination});

  Color get _diffColor {
    if (destination.rating >= 4.9) return AppTheme.primary;
    if (destination.rating >= 4.7) return const Color(0xFFFFC107);
    return const Color(0xFF2ECC71);
  }

  String get _diffLabel {
    if (destination.rating >= 4.9) return 'HARD';
    if (destination.rating >= 4.7) return 'MOD';
    return 'EASY';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/listings/${destination.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                destination.imageUrl,
                width: 72, height: 72, fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(destination.name,
                      style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on, size: 12, color: AppTheme.textSecondary),
                    Text(destination.country,
                        style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textSecondary)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    children: destination.tags.take(2).map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(t.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.primary, letterSpacing: 0.5)),
                    )).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _diffColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_diffLabel,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _diffColor, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 6),
                Text('\$${destination.pricePerNight.toInt()}/n',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
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
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=800&q=80',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🎒 COMMUNITY',
                      style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.primary, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text('JOIN THE\nTRIBE',
                      style: GoogleFonts.bebasNeue(fontSize: 24, color: Colors.white, height: 1)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Connect Now',
                        style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
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

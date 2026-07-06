import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/state_views.dart';

class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key});

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  // Discover owns its category in LOCAL state. Routing it through
  // GemProvider.selectCategory / .gems would also filter the Map markers,
  // which share that state — so the grid reads the PURE search(category:)
  // method instead and the Map is never touched.
  String _selectedCat = 'all';

  void _comingSoonSave(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving gems is coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    final featured = gem.featured; // GLOBAL trending — independent of the grid
    final results = gem.search(query: '', category: _selectedCat);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Discover'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: _CategoryBar(
                selected: _selectedCat,
                onSelect: (cat) => setState(() => _selectedCat = cat),
              ),
            ),
          ),

          // ── FEATURED GEMS (global trending; not affected by the category bar)
          if (featured.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Featured Gems',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
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
                      color: AppTheme.textPrimary)),
            ),
          ),

          // ── GRID STATES (loading / error / empty / data)
          if (gem.loading)
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
          else if (results.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyStateView(text: 'No gems here yet.'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _GemCard(
                    gem: results[i],
                    onSave: () => _comingSoonSave(ctx),
                  ),
                  childCount: results.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
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
          final label =
              isAll ? 'All' : cat[0].toUpperCase() + cat.substring(1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onSelect(cat),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
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
        onTap: () => context.go('/gems/${gem.id}'),
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
        return (color: AppTheme.textSecondary, label: d.toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _difficulty;
    return Semantics(
      button: true,
      label: gem.gemName,
      child: GestureDetector(
        onTap: () => context.go('/gems/${gem.id}'),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
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
                              size: 18, color: AppTheme.textSecondary),
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
                        child: Text(gem.displayCategory,
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
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (gem.gemLocation != null &&
                        gem.gemLocation!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(gem.gemLocation!,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11),
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

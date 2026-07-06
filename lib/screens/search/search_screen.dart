import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/state_views.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  // Screen-local search state. Deliberately NOT in GemProvider: routing the
  // query/category through the provider would also filter the Map and Home,
  // which share that state. Search stays pure and local.
  String _query = '';
  String _selectedCat = 'all';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() => _query = value);

  void _applyChip(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
  }

  void _toggleCat(String cat) {
    setState(() => _selectedCat = _selectedCat == cat ? 'all' : cat);
  }

  @override
  Widget build(BuildContext context) {
    final gem = context.watch<GemProvider>();
    final showSuggestions = _query.isEmpty && _selectedCat == 'all';
    final results = gem.search(query: _query, category: _selectedCat);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _setQuery,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search gems, places…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: showSuggestions
          ? _Suggestions(
              selectedCat: _selectedCat,
              onCategory: _toggleCat,
              popular: gem.popularTerms,
              onChip: _applyChip,
            )
          : Builder(
              builder: (context) {
                if (gem.loading) return const FeaturedRowSkeleton();
                if (gem.error != null) {
                  return ErrorStateView(
                      onRetry: gem.refresh, message: gem.error);
                }
                if (results.isEmpty) {
                  return const EmptyStateView(text: 'No gems match that yet.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: results.length,
                  itemBuilder: (ctx, i) => _GemResultRow(gem: results[i]),
                );
              },
            ),
    );
  }
}

/// Categories grid (All + each gem category) and derived popular-term chips.
/// Shown only when there's no active query and no category selected.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.selectedCat,
    required this.onCategory,
    required this.popular,
    required this.onChip,
  });

  final String selectedCat;
  final ValueChanged<String> onCategory;
  final List<String> popular;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) {
    // 'all' first (primary reset), then the gem categories.
    final cats = <String>['all', ...Gem.categories];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Categories',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.9,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: cats.length,
          itemBuilder: (ctx, i) {
            final cat = cats[i];
            final isAll = cat == 'all';
            final selected = selectedCat == cat;
            final icon =
                isAll ? Icons.public : AppConstants.gemCategoryIcons[cat]!;
            final label = isAll
                ? 'All'
                : cat[0].toUpperCase() + cat.substring(1);
            return _CategoryTile(
              icon: icon,
              label: label,
              selected: selected,
              onTap: () => onCategory(cat),
            );
          },
        ),
        const SizedBox(height: 24),
        const Text('Popular Searches',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
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
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.trending_up,
                              size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(term,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary
                    : AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(icon,
                    size: 26,
                    color: selected ? Colors.white : AppTheme.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textPrimary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _GemResultRow extends StatelessWidget {
  const _GemResultRow({required this.gem});

  final Gem gem;

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
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              AppNetworkImage(
                url: gem.photoUrl ?? '',
                width: 70,
                height: 70,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gem.displayCategory.toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(gem.gemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppTheme.textPrimary)),
                    if (gem.gemLocation != null &&
                        gem.gemLocation!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 13, color: AppTheme.textSecondary),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(gem.gemLocation!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13)),
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

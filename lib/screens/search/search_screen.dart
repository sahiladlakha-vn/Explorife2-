import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/destination_provider.dart';
import '../../models/destination.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _hasQuery = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final q = _controller.text;
      context.read<DestinationProvider>().setSearchQuery(q);
      setState(() => _hasQuery = q.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = context.watch<DestinationProvider>().destinations;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search destinations, countries...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _hasQuery
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      context.read<DestinationProvider>().setSearchQuery('');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _hasQuery ? _SearchResults(results: results) : _SearchSuggestions(),
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  final List<String> _popular = ['Beach', 'Mountains', 'Tokyo', 'Bali', 'Europe', 'Adventure'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
            itemCount: AppConstants.categories.length,
            itemBuilder: (ctx, i) {
              final cat = AppConstants.categories[i];
              return GestureDetector(
                onTap: () {
                  context.read<DestinationProvider>().selectCategory(cat);
                  context.go('/listings');
                },
                child: Column(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(AppConstants.categoryIcons[i],
                            style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(cat,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Popular Searches',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popular.map((term) => GestureDetector(
              onTap: () => context.read<DestinationProvider>().setSearchQuery(term),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(term, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<Destination> results;
  const _SearchResults({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text('No destinations found',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final d = results[i];
        return GestureDetector(
          onTap: () => context.go('/listings/${d.id}'),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    d.imageUrl,
                    width: 70, height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 13, color: AppTheme.textSecondary),
                          Text(d.country,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(d.category,
                                style: const TextStyle(
                                    color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                          const Spacer(),
                          const Icon(Icons.star, size: 13, color: Colors.amber),
                          Text(' ${d.rating}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

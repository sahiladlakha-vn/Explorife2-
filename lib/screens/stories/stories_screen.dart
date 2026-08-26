import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/layout/max_width_center.dart';
import '../../core/theme/app_theme.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';

class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StoryProvider>();
    final q = _query.trim().toLowerCase();
    // Real filter: title/excerpt substring match, applied on top of the
    // category chips' own filtering (prov.stories is already category-scoped).
    final stories = q.isEmpty
        ? prov.stories
        : prov.stories
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                (s.excerpt?.toLowerCase().contains(q) ?? false))
            .toList();
    final featured = prov.featuredStories;

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: MaxWidthCenter(
        child: RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.lightCard,
          onRefresh: prov.refresh,
          child: CustomScrollView(
            slivers: [
              // App bar
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.lightSurface,
                title: Text('FIELD JOURNAL',
                    style: GoogleFonts.bebasNeue(
                        fontSize: 24,
                        letterSpacing: 0.5,
                        color: AppTheme.lightInk)),
                actions: [
                  // Desktop-only: RefreshIndicator's pull gesture isn't
                  // discoverable with a mouse + scrollwheel, so this gives
                  // desktop an explicit way to trigger the same prov.refresh.
                  if (Breakpoints.isDesktop(context))
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppTheme.lightInk),
                      tooltip: 'Refresh',
                      onPressed: prov.refresh,
                    ),
                  IconButton(
                    icon: Icon(_searchOpen ? Icons.close : Icons.search,
                        color: AppTheme.lightInk),
                    tooltip: _searchOpen ? 'Close search' : 'Search stories',
                    onPressed: _toggleSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: AppTheme.lightInk),
                    tooltip: 'Submit Story',
                    onPressed: () => context.go('/submit-story'),
                  ),
                ],
              ),

              if (_searchOpen)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      style: GoogleFonts.fredoka(
                          color: AppTheme.lightInk, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search stories…',
                        hintStyle: GoogleFonts.fredoka(
                            color: AppTheme.lightMute, fontSize: 14),
                        prefixIcon: const Icon(Icons.search,
                            color: AppTheme.lightMute, size: 20),
                        filled: true,
                        fillColor: AppTheme.lightCard,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.lightBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.lightBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primary),
                        ),
                      ),
                    ),
                  ),
                ),

              // Featured hero (first featured story) — hidden while searching,
              // same reasoning Listings' Suggestions state hides Browse content.
              if (featured.isNotEmpty && !_searchOpen)
                SliverToBoxAdapter(
                  child: _FeaturedHero(story: featured.first),
                ),

              // Filter chips
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: ['All', ...Story.adventureTypes].map((f) {
                      final sel = prov.activeFilter == f;
                      return GestureDetector(
                        onTap: () => context.read<StoryProvider>().setFilter(f),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.primary : AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel
                                    ? AppTheme.primary
                                    : AppTheme.lightBorder),
                          ),
                          child: Text(f,
                              style: GoogleFonts.fredoka(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : AppTheme.lightMute,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Loading
              if (prov.loading)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  ),
                )
              else if (stories.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(60),
                      child: Column(children: [
                        const Text('📖', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 16),
                        Text('No stories yet',
                            style: GoogleFonts.bebasNeue(
                                fontSize: 24, color: AppTheme.lightMute)),
                        const SizedBox(height: 8),
                        Text('Be the first to share your adventure',
                            style: GoogleFonts.fredoka(
                                color: AppTheme.lightMute, fontSize: 14)),
                      ]),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _StoryCard(story: stories[i]),
                      childCount: stories.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/submit-story'),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Write',
            style: GoogleFonts.fredoka(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _FeaturedHero extends StatelessWidget {
  final Story story;
  const _FeaturedHero({required this.story});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/stories/${story.id}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            story.hasPhoto
                ? Image.network(story.photo, fit: BoxFit.cover)
                : Container(color: AppTheme.lightCard),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85)
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('⭐ FEATURED',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: Colors.white)),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (story.adventureType != null)
                      Text(story.adventureType!.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.primary)),
                    const SizedBox(height: 4),
                    Text(story.title,
                        style: GoogleFonts.bebasNeue(
                            fontSize: 26,
                            color: Colors.white,
                            letterSpacing: 0.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(story.displayAuthor,
                          style: GoogleFonts.fredoka(
                              fontSize: 12, color: Colors.white70)),
                      if (story.location != null) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(story.location!,
                            style: GoogleFonts.fredoka(
                                fontSize: 12, color: Colors.white70)),
                      ],
                    ]),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Full-width photo card — photo on top with a category pill overlaid at its
/// top-left corner, title + excerpt + author row below. Replaces an earlier
/// horizontal thumbnail-row layout to match the reference design's vertical
/// card shape.
class _StoryCard extends StatelessWidget {
  final Story story;
  const _StoryCard({required this.story});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/stories/${story.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo + overlaid category pill
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  story.hasPhoto
                      ? Image.network(story.photo, fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.lightBorder,
                          child: Center(
                            child: Text(story.typeEmoji_,
                                style: const TextStyle(fontSize: 40)),
                          ),
                        ),
                  if (story.adventureType != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(story.adventureType!.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  if (story.featured)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star,
                            size: 14, color: AppTheme.primary),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(story.title,
                      style: GoogleFonts.fredoka(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.lightInk),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (story.excerpt != null) ...[
                    const SizedBox(height: 4),
                    Text(story.excerpt!,
                        style: GoogleFonts.fredoka(
                            fontSize: 13,
                            color: AppTheme.lightMute,
                            height: 1.4),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                      child: const Icon(Icons.person,
                          size: 12, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 6),
                    Text(story.displayAuthor,
                        style: GoogleFonts.fredoka(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.lightInk)),
                    if (story.location != null) ...[
                      Text('  ·  ',
                          style: GoogleFonts.fredoka(
                              fontSize: 12, color: AppTheme.lightMute)),
                      Expanded(
                        child: Text(story.location!,
                            style: GoogleFonts.fredoka(
                                fontSize: 12, color: AppTheme.lightMute),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

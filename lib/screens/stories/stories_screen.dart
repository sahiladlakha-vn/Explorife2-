import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';

class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StoryProvider>();
    final stories = prov.stories;
    final featured = prov.featuredStories;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onRefresh: prov.refresh,
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              pinned: true,
              backgroundColor: AppTheme.bg,
              title: Text('FIELD JOURNAL',
                  style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Submit Story',
                  onPressed: () => context.go('/submit-story'),
                ),
              ],
            ),

            // Featured hero (first featured story)
            if (featured.isNotEmpty)
              SliverToBoxAdapter(
                child: _FeaturedHero(story: featured.first),
              ),

            // Filter chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: ['All', ...Story.adventureTypes].map((f) {
                    final sel = prov.activeFilter == f;
                    return GestureDetector(
                      onTap: () => context.read<StoryProvider>().setFilter(f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? AppTheme.primary : AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppTheme.primary : AppTheme.divider),
                        ),
                        child: Text(f,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : AppTheme.textSecondary,
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
                          style: GoogleFonts.bebasNeue(fontSize: 24, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      Text('Be the first to share your adventure',
                          style: GoogleFonts.dmSans(color: AppTheme.textSecondary, fontSize: 14)),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/submit-story'),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.edit, color: Colors.white),
        label: Text('Write Story',
            style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
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
                : Container(color: AppTheme.surface2),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('⭐ FEATURED',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white)),
              ),
            ),
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (story.adventureType != null)
                  Text(story.adventureType!.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.primary)),
                const SizedBox(height: 4),
                Text(story.title,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 26, color: Colors.white, letterSpacing: 0.5),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.person_outline, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(story.displayAuthor,
                      style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white70)),
                  if (story.location != null) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_outlined, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(story.location!,
                        style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white70)),
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

class _StoryCard extends StatelessWidget {
  final Story story;
  const _StoryCard({required this.story});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/stories/${story.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: SizedBox(
              width: 100, height: 110,
              child: story.hasPhoto
                  ? Image.network(story.photo, fit: BoxFit.cover)
                  : Container(
                      color: AppTheme.surface2,
                      child: Center(
                        child: Text(story.typeEmoji_,
                            style: const TextStyle(fontSize: 32)),
                      ),
                    ),
            ),
          ),
          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (story.adventureType != null)
                  Row(children: [
                    Text(story.typeEmoji_, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(story.adventureType!.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 9, color: AppTheme.primary, letterSpacing: 0.5)),
                    if (story.featured) ...[
                      const Spacer(),
                      const Icon(Icons.star, size: 12, color: AppTheme.primary),
                    ],
                  ]),
                const SizedBox(height: 4),
                Text(story.title,
                    style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if (story.excerpt != null)
                  Text(story.excerpt!,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.person_outline, size: 11, color: AppTheme.textSecondary),
                  const SizedBox(width: 3),
                  Text(story.displayAuthor,
                      style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textSecondary)),
                  if (story.location != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.location_on_outlined, size: 11, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(story.location!,
                          style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

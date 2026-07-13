part of '../profile_screen.dart';

// My Stories tab.
//
// Reads the owner-view cache (`StoryProvider.myStories`) rather than a prop:
// this is the user's OWN submissions, including pending/rejected, and is loaded
// by-email on profile mount. It is deliberately NOT the shell's approved-only
// `myStories` list (that one still feeds the Overview RECENT STORIES card and
// the badge count). Four states — error, loading, empty, populated — mirror the
// shared state_views contract used everywhere else.

// ─────────────────────────────────────────
// MY STORIES TAB
// ─────────────────────────────────────────
class _StoriesTab extends StatelessWidget {
  const _StoriesTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoryProvider>();
    final auth = context.read<AuthProvider>();
    final email = auth.user?.email;

    // ERROR — a real fetch failure (not RLS-filtered rows, which return an
    // empty-but-successful list). Retry re-runs the by-email load, forced.
    if (provider.myStoriesError != null && provider.myStories.isEmpty) {
      return ErrorStateView(
        message: 'Check your connection and try again.',
        onRetry: () {
          if (email != null) {
            context.read<StoryProvider>().loadMyStories(email, force: true);
          }
        },
      );
    }

    // LOADING — only the initial fetch (empty cache). A refresh over a warm
    // cache keeps the list on screen rather than flashing skeletons.
    if (provider.myStoriesLoading && provider.myStories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
        children: const [
          _Card(
            child: Column(
              children: [
                _StorySkeletonRow(),
                _StorySkeletonRow(divider: true),
                _StorySkeletonRow(divider: true),
              ],
            ),
          ),
        ],
      );
    }

    // EMPTY — no submissions yet. Same copy/CTA as before.
    if (provider.myStories.isEmpty) {
      return _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No stories yet',
        subtitle: 'Share your first adventure with the tribe.',
        cta: 'Submit a story',
        onTap: () => context.go('/submit-story'),
      );
    }

    // POPULATED — owner's stories, newest first. Pending rows light the
    // goldenrod PENDING pill via _StoryRow's existing status logic.
    final stories = provider.myStories;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _Card(
          child: Column(
            children: stories
                .asMap()
                .entries
                .map((e) => _StoryRow(story: e.value, divider: e.key > 0))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// Skeleton row shaped to the _StoryRow layout, shown only on the initial
// owner-stories fetch. Divider matches _StoryRow's inter-row rule.
class _StorySkeletonRow extends StatelessWidget {
  final bool divider;
  const _StorySkeletonRow({this.divider = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider
            ? const Border(top: BorderSide(color: _kBorder))
            : null,
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 160, height: 14),
                SizedBox(height: 8),
                Skeleton(width: 100, height: 11),
              ],
            ),
          ),
          SizedBox(width: 12),
          Skeleton(width: 64, height: 20, radius: 6),
        ],
      ),
    );
  }
}


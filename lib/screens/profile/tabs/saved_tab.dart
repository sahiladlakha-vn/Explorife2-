part of '../profile_screen.dart';

// Saved Gems tab — reads the signed-in user's gem_saves via GemProvider.

// ─────────────────────────────────────────
// SAVED GEMS TAB
// ─────────────────────────────────────────
class _SavedTab extends StatelessWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GemProvider>();

    if (gp.savedHasError) {
      return ErrorStateView(
        message: "Couldn't load your saved gems.",
        onRetry: () => context.read<GemProvider>().loadSaved(force: true),
      );
    }

    // `initial` means the mount hook hasn't fired yet; treat it as loading so
    // the tab never flashes the empty state before the first fetch resolves.
    final loading = gp.savedStatus == GemStatus.initial ||
        gp.savedStatus == GemStatus.loading;
    if (loading && gp.savedGems.isEmpty) return const _SavedSkeletonGrid();

    final saved = gp.savedGems;
    if (saved.isEmpty) {
      return EmptyStateView(
        icon: Icons.diamond_outlined,
        text: "Nothing saved yet — bookmark spots and they'll show up here.",
        onAction: () => context.go('/explore'),
        actionLabel: 'Explore the map',
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: [for (final g in saved) _SavedGemCard(gem: g)],
    );
  }
}

class _SavedGemCard extends StatelessWidget {
  final Gem gem;
  const _SavedGemCard({required this.gem});

  @override
  Widget build(BuildContext context) {
    final photo = gem.photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return GestureDetector(
      onTap: () => context.go('/gems/${gem.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              AppNetworkImage(
                url: photo,
                fit: BoxFit.cover,
                semanticLabel: gem.gemName,
              )
            else
              const _PhotolessTile(),
            // Bottom scrim so the white name stays legible over either tile.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                gem.gemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => context.read<GemProvider>().toggleSave(gem),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite,
                      size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder tile for a saved gem with no photo — a category-neutral marker on
// the card surface, still under the scrim so the name reads.
class _PhotolessTile extends StatelessWidget {
  const _PhotolessTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kCard,
      alignment: Alignment.center,
      child: const Icon(Icons.place, size: 34, color: _kBorder),
    );
  }
}

class _SavedSkeletonGrid extends StatelessWidget {
  const _SavedSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: List.generate(4, (_) => const Skeleton(radius: 14)),
    );
  }
}

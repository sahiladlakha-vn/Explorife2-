part of '../profile_screen.dart';

// Badges tab — a pure render of evaluateBadges() output assembled in the shell.
//
// SKELETON (canary): earned/locked is a BINARY visual treatment for v1. The
// tile chrome maps onto the repo's existing state convention (alpha-tinted solid
// border + full-colour icon for the "on" state; _kMute/_kBorder dimmed for the
// "off" state — the same language _StoryRow's status pills use). No dashed
// border: the design system has no dashed primitive, so its equivalent is the
// dimmed-solid treatment here.
//
// PROGRESS: no bar/ring in v1. Locked tiles instead show the honest
// `current/threshold` count (a badge shouldn't be opaque about how near it is),
// and earned tiles show "EARNED". BadgeProgress.progress/.current are already on
// hand, so a graphical ring is a later additive change to [_BadgeTile] alone.

// ─────────────────────────────────────────
// BADGES TAB
// ─────────────────────────────────────────
class _BadgesTab extends StatelessWidget {
  /// Pre-evaluated in the shell (one source, next to the alerts computation).
  final List<BadgeProgress> badges;
  const _BadgesTab({required this.badges});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.82,
      children: [for (final b in badges) _BadgeTile(badge: b)],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final BadgeProgress badge;
  const _BadgeTile({required this.badge});

  // Metric → glyph, reusing the same icons the tab bar / cards already use so
  // the badge for a metric reads as the same thing everywhere.
  static IconData _iconFor(BadgeMetric m) => switch (m) {
        BadgeMetric.gems => Icons.diamond_outlined,
        BadgeMetric.trips => Icons.map_outlined,
        BadgeMetric.stories => Icons.menu_book_outlined,
        BadgeMetric.bookings => Icons.confirmation_number_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    final accent = earned ? AppTheme.primary : _kMute;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: earned ? AppTheme.primary.withValues(alpha: 0.5) : _kBorder,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: earned
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : _kBorder.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(badge.def.metric), size: 22, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            badge.def.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.fredoka(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: earned ? _kInk : _kMute,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            earned ? 'EARNED' : '${badge.current}/${badge.def.threshold}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

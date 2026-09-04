import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// A verified business's linked-listing card, shown on Gem Detail below the
/// existing curated accordion. Generalized out of Attraction's original
/// `_AttractionInfoCard` when Restaurant became the second business type to
/// need the exact same "VERIFIED BUSINESS LISTING" card shape — see
/// docs/audits/restaurant-business-profile-2026-09-05.md for why this was
/// generalized now rather than forking a second copy: with an 8-type
/// roadmap, every additional type would otherwise duplicate this same
/// badge/info-rows/"View full listing" shell.
///
/// Deliberately its own card, not styled to blend into the accordion above
/// it: this is business-provided information, not editorial content, and
/// the "Verified Business" badge only means anything if it visually reads
/// as a distinct source. A Gem's own curated content (description, photos)
/// is never replaced or merged by this — it only ever appears as an
/// ADDITIONAL section.
class LinkedBusinessCard extends StatelessWidget {
  const LinkedBusinessCard({
    super.key,
    required this.rows,
    required this.detailRoute,
  });

  /// The business-provided facts to show (entry fee/hours for an
  /// Attraction; price range/reservation for a Restaurant, etc.) — order
  /// matters, rendered top to bottom.
  final List<LinkedBusinessInfoRow> rows;

  /// Where "View full listing" navigates — e.g. '/attractions/$id' or
  /// '/restaurants/$id'.
  final String detailRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text('VERIFIED BUSINESS LISTING',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => context.push(detailRoute),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View full listing',
                    style: GoogleFonts.fredoka(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 14, color: AppTheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One icon/label/value row inside a [LinkedBusinessCard] — the same
/// visual shape as the private `_InfoTile` GemDetailScreen already used for
/// Attraction, made public and reusable so every business type feeds the
/// same card the same way instead of forking its own info-tile widget.
class LinkedBusinessInfoRow extends StatelessWidget {
  const LinkedBusinessInfoRow(
      {super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.lightMute)),
          Text(value,
              style:
                  GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
        ]),
      ]),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';

/// How a [GemCard] lays itself out.
///
/// * [compact] — fixed-width vertical card (legacy carousel sizing).
/// * [full]    — full-width vertical card for the expanded list feed.
/// * [deck]    — full-width HORIZONTAL card (thumbnail left, text right) for the
///   floating card deck that browses gems over the map.
///
/// All variants render the *same* slots from the *same* [Gem]; only layout and
/// sizing differ, so there is exactly one card implementation to maintain.
enum GemCardVariant { compact, full, deck }

/// One reusable discovery-feed card, driven entirely by a typed [Gem] plus
/// presentational callbacks. It contains **no** Supabase or business logic: the
/// save state is passed in ([isSaved]) and toggled via [onToggleSave] so the
/// owning provider stays the single source of truth, and every metadata element
/// is an OPTIONAL slot that simply disappears when its data is absent. This is
/// what lets a fully-populated gem and a sparse one both render correctly
/// without branching at the call site.
class GemCard extends StatelessWidget {
  const GemCard({
    super.key,
    required this.gem,
    required this.categoryIcon,
    this.variant = GemCardVariant.compact,
    this.isSaved = false,
    this.onTap,
    this.onToggleSave,
    this.distanceLabel,
    this.rating,
    this.savesLabel,
  });

  final Gem gem;
  final IconData categoryIcon;
  final GemCardVariant variant;

  /// Whether the save toggle reads as saved. Owned by state, never by the card.
  final bool isSaved;
  final VoidCallback? onTap;
  final VoidCallback? onToggleSave;

  /// Pre-computed distance label (e.g. "1.2 km"); null hides the lime pill.
  final String? distanceLabel;

  /// Optional rating; null hides the star metric. Empty for v1.
  final double? rating;

  /// Optional saves label (e.g. "320 saves"); null hides it. Empty for v1.
  final String? savesLabel;

  bool get _isCompact => variant == GemCardVariant.compact;
  bool get _isDeck => variant == GemCardVariant.deck;

  // ── token-driven sizing (the only place card geometry is defined) ──
  static const double compactWidth = 210;
  static const double _compactImageHeight = 124;
  static const double _fullImageHeight = 168;
  /// Corner radius shared by every card variant. Public so the loading
  /// skeleton can mirror the real card's shape from one source of truth.
  static const double radius = 18;
  static const double _radius = radius;

  /// Height of the floating deck card. The square thumbnail ([deckThumb]) plus
  /// the card's 12px vertical padding (12 + 80 + 12) lands exactly here.
  static const double deckHeight = 104;

  /// Side of the deck card's square thumbnail. Public so the loading skeleton's
  /// thumbnail block matches the real deck card exactly.
  static const double deckThumb = 80;
  static const double _deckThumb = deckThumb;

  /// Corner radius of the deck thumbnail (smaller than the card's [radius]).
  static const double _deckThumbRadius = 14;

  // Reserve exactly two lines for the tagline so cards align whether the
  // tagline is one line, two lines, or absent.
  static const double _taglineFontSize = 12.5;
  static const double _taglineLineHeight = 1.3;
  static const double _taglineReserved =
      _taglineFontSize * _taglineLineHeight * 2;

  @override
  Widget build(BuildContext context) {
    final card = _isDeck ? _deckCard() : _verticalCard();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  // ── vertical card (compact carousel + full list) ──
  Widget _verticalCard() {
    return Container(
      width: _isCompact ? compactWidth : double.infinity,
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _imageBlock(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _title(),
                const SizedBox(height: 3),
                _taglineSlot(),
                const SizedBox(height: 8),
                _metaRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── horizontal deck card (thumbnail left, text right) ──
  // Reuses the same Gem slots as the vertical cards: square thumbnail with the
  // distance pill overlaid, then a right column of category · title · meta with
  // the bookmark toggle pinned top-right.
  Widget _deckCard() {
    return Container(
      width: double.infinity,
      height: deckHeight,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 80px rounded thumbnail with the lime distance badge anchored
          // bottom-left, exactly as the layout mockup shows.
          ClipRRect(
            borderRadius: BorderRadius.circular(_deckThumbRadius),
            child: SizedBox(
              width: _deckThumb,
              height: _deckThumb,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _photoOrFallback(),
                  if (distanceLabel != null)
                    Positioned(left: 6, bottom: 6, child: _distancePill()),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _deckCategory(),
                const SizedBox(height: 2),
                _title(),
                const SizedBox(height: 6),
                _metaRow(),
              ],
            ),
          ),
          // Bookmark as a light circular button pinned to the card's top-right
          // (its own slot), instead of the dark on-image toggle.
          if (onToggleSave != null) ...[
            const SizedBox(width: 8),
            _deckSaveToggle(),
          ],
        ],
      ),
    );
  }

  /// Deck-card bookmark: a light grey circular button (top-right), distinct from
  /// the dark translucent [_saveToggle] used over photos.
  Widget _deckSaveToggle() {
    return GestureDetector(
      onTap: onToggleSave,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSaved
              ? AppTheme.primary.withValues(alpha: 0.12)
              : const Color(0xFFF3F3F3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSaved ? Icons.bookmark : Icons.bookmark_border,
          size: 17,
          color: isSaved ? AppTheme.primary : const Color(0xFF555555),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppTheme.sheetSurface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppTheme.sheetBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// Inline category label for the deck card (icon + name in brand colour),
  /// the light-surface counterpart to the dark [_categoryPill] used on images.
  Widget _deckCategory() {
    if (gem.category == null) return const SizedBox.shrink();
    // Orange uppercase eyebrow (no icon), matching the layout mockup.
    return Text(
      gem.displayCategory.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppTheme.primary,
      ),
    );
  }

  // ── image + overlays ──
  Widget _imageBlock() {
    final height = _isCompact ? _compactImageHeight : _fullImageHeight;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius)),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _photoOrFallback(),
            // Bottom gradient scrim so overlaid pills stay legible on any image.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
            if (gem.category != null)
              Positioned(top: 8, left: 8, child: _categoryPill()),
            if (onToggleSave != null)
              Positioned(top: 8, right: 8, child: _saveToggle()),
            if (distanceLabel != null)
              Positioned(left: 8, bottom: 8, child: _distancePill()),
          ],
        ),
      ),
    );
  }

  Widget _photoOrFallback() {
    final url = gem.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppTheme.sheetBorder),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  /// Photo-less fallback. The deck variant uses a DEEP brand tint with a clearly
  /// visible category icon (not the washed-out watermark the larger vertical
  /// cards use), so the small 80px thumbnail still reads as branded content.
  Widget _fallback() {
    if (_isDeck) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB05A2E), Color(0xFF7A3D1E)],
          ),
        ),
        child: Center(
          child: Icon(
            categoryIcon,
            size: 32,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.22),
            AppTheme.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          categoryIcon,
          size: _isCompact ? 52 : 72,
          color: AppTheme.primary.withValues(alpha: 0.18),
        ),
      ),
    );
  }

  Widget _categoryPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        color: Colors.black.withValues(alpha: 0.45),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(categoryIcon, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              gem.displayCategory,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveToggle() {
    return GestureDetector(
      onTap: onToggleSave,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isSaved
              ? AppTheme.primary
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSaved ? Icons.bookmark : Icons.bookmark_border,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _distancePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lime,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.near_me, size: 11, color: Color(0xFF0C0C0C)),
          const SizedBox(width: 3),
          Text(
            distanceLabel!,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0C0C0C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title() {
    return Text(
      gem.gemName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.dmSans(
        fontSize: variant == GemCardVariant.full ? 17 : 15,
        fontWeight: FontWeight.w700,
        color: AppTheme.sheetInk,
        height: 1.1,
      ),
    );
  }

  /// Tagline in a fixed-height box (two reserved lines) so every card's meta row
  /// sits at the same vertical position, taglines or not.
  Widget _taglineSlot() {
    final tagline = gem.tagline;
    return SizedBox(
      height: _taglineReserved,
      width: double.infinity,
      child: (tagline != null && tagline.isNotEmpty)
          ? Text(
              tagline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: _taglineFontSize,
                height: _taglineLineHeight,
                fontStyle: FontStyle.italic,
                color: AppTheme.sheetSubInk,
              ),
            )
          : null,
    );
  }

  /// Rating · saves · @handle — each metric collapses when its data is missing.
  /// When there are no community metrics yet, a small "New" tag stands in
  /// rather than fabricating numbers.
  Widget _metaRow() {
    final parts = <Widget>[];

    if (rating != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFF8A00)),
          const SizedBox(width: 2),
          Text(
            rating!.toStringAsFixed(1),
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.sheetInk,
            ),
          ),
        ],
      ));
    }

    if (savesLabel != null) {
      parts.add(_metaText(savesLabel!));
    }

    if (gem.dropperHandle != null && gem.dropperHandle!.isNotEmpty) {
      parts.add(Flexible(child: _metaText('@${gem.dropperHandle!}')));
    }

    if (rating == null && savesLabel == null) {
      parts.insert(0, _newTag());
    }

    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) children.add(_dot());
      children.add(parts[i]);
    }

    return SizedBox(
      height: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _metaText(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.sheetSubInk),
      );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          '·',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.sheetSubInk),
        ),
      );

  Widget _newTag() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'New',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
      );
}

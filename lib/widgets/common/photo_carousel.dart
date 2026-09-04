import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../app_network_image.dart';

/// Full-bleed photo carousel with dot-indicator pagination and floating
/// overlay controls (back/save/share, whatever the caller needs) — the
/// shared hero component for any detail screen with a photo gallery. Owns
/// its own page/index state, so callers don't need a PageController of
/// their own.
///
/// One component whether there are 0, 1, or many photos — never a
/// different layout for the single-photo case: zero photos shows
/// [emptyIcon]/[emptyEmoji] instead of a page view, and a single photo
/// disables swipe physics (nothing to swipe to) but still renders through
/// the same [PageView.builder].
///
/// Originally built for GemDetailScreen, extracted so TourDetailScreen (and
/// any future detail screen) reuses it instead of forking a second
/// implementation.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({
    super.key,
    required this.photos,
    this.captionFor,
    this.emptyIcon,
    this.emptyEmoji,
    this.semanticLabel,
    this.aspectRatio = 4 / 3,
    this.topLeft,
    this.topRight,
  });

  final List<String> photos;

  /// Optional per-photo caption, shown below the hero for the currently
  /// visible photo only. Null (or returning null for a given photo) means
  /// no caption row renders — never fabricated.
  final String? Function(String photo)? captionFor;

  /// Shown centered when [photos] is empty. If both are null, falls back
  /// to a generic pin emoji.
  final IconData? emptyIcon;
  final String? emptyEmoji;

  final String? semanticLabel;
  final double aspectRatio;

  /// Floating overlay slots over the hero photo, top-left/top-right (e.g.
  /// a back button, save + share icons) — any widget, including a Row of
  /// several icons. Null means that side renders nothing.
  final Widget? topLeft;
  final Widget? topRight;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpTo(int i) {
    setState(() => _index = i);
    _controller.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final count = photos.length;
    final hasMultiple = count > 1;
    final currentCaption = photos.isNotEmpty && widget.captionFor != null
        ? widget.captionFor!(photos[_index])
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photos.isEmpty)
                Container(
                  color: AppTheme.lightCard,
                  child: Center(
                    child: widget.emptyIcon != null
                        ? Icon(widget.emptyIcon, size: 64, color: AppTheme.lightMute)
                        : Text(widget.emptyEmoji ?? '📍',
                            style: const TextStyle(fontSize: 64)),
                  ),
                )
              else
                PageView.builder(
                  controller: _controller,
                  physics: hasMultiple
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: count,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => AppNetworkImage(
                      url: photos[i], semanticLabel: widget.semanticLabel),
                ),
              // Scrim so the floating icons stay legible over a bright photo.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 96,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x59000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
              if (widget.topLeft != null || widget.topRight != null)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        widget.topLeft ?? const SizedBox.shrink(),
                        widget.topRight ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              if (photos.isNotEmpty)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count; i++)
                        Semantics(
                          button: true,
                          label: 'Photo ${i + 1} of $count',
                          selected: i == _index,
                          child: GestureDetector(
                            onTap: () => _jumpTo(i),
                            behavior: HitTestBehavior.opaque,
                            // Padding (not just the visible dot) is the real
                            // tap target — the dot itself stays visually
                            // small by design (a dense multi-photo carousel
                            // can have many of these in a row), but the
                            // hit area is meaningfully larger than the 6px
                            // dot alone. Physical space rules out the full
                            // ~44px guideline here without dots overlapping
                            // when there are several photos.
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: i == _index ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _index
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (currentCaption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(currentCaption,
                style: GoogleFonts.fredoka(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.lightMute)),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'feed_metrics.dart';
import 'gem_card.dart';

/// Full-screen "preparing the map" state shown ONLY while the gem fetch is
/// pending (or has errored). It is driven entirely by [GemProvider.status] from
/// the call site — this widget owns no timer and enforces no minimum duration,
/// so a fast fetch flashes it briefly and a slow one holds it until the future
/// completes.
///
/// Layout mirrors the live map it replaces: a light canvas with a pulsing
/// location beacon, and a bottom card whose skeleton is built from the same
/// [GemCard] deck constants as the real cards, so any card-shape change stays in
/// one place.
class MapLoadingOverlay extends StatefulWidget {
  const MapLoadingOverlay({
    super.key,
    this.userLat,
    this.userLng,
    this.isError = false,
    this.onRetry,
  });

  /// User location, used to place the beacon. When null the beacon centres on
  /// the screen (we're still locating the user).
  final double? userLat;
  final double? userLng;

  /// When true the fetch failed: show a brief retry state instead of spinning
  /// forever.
  final bool isError;
  final VoidCallback? onRetry;

  @override
  State<MapLoadingOverlay> createState() => _MapLoadingOverlayState();
}

class _MapLoadingOverlayState extends State<MapLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _beacon =
      AnimationController(vsync: this, duration: kBeaconPulse)..repeat();
  late final AnimationController _shimmer =
      AnimationController(vsync: this, duration: kSkeletonShimmer)..repeat();

  @override
  void dispose() {
    _beacon.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Material(
        color: AppTheme.lightSurface,
        child: Stack(
          children: [
            // Subtle orange dotted texture over the light canvas.
            const Positioned.fill(
              child: CustomPaint(painter: _DottedTexturePainter()),
            ),

            // Pulsing location beacon (hidden in the error state — nothing to
            // locate towards while we're showing a failure).
            if (!widget.isError)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _beacon,
                  builder: (_, __) =>
                      CustomPaint(painter: _BeaconPainter(_beacon.value)),
                ),
              ),

            // Bottom card: spinner + status line + GemCard-shaped skeleton, or
            // the retry state on error.
            Positioned(
              left: 16,
              right: 16,
              bottom: 28 + MediaQuery.of(context).padding.bottom,
              child: widget.isError ? _errorCard() : _loadingCard(),
            ),
          ],
        ),
      ),
    );
  }

  // ───────── loading card ─────────

  Widget _loadingCard() => _cardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Finding gems near you…',
                  style: GoogleFonts.fredoka(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.sheetInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Skeleton mirrors the GemCard deck variant: square thumbnail block
            // on the left, title bar + meta bar stacked on the right.
            SizedBox(
              height: GemCard.deckThumb,
              child: Row(
                children: [
                  _skeleton(
                    width: GemCard.deckThumb,
                    height: GemCard.deckThumb,
                    radius: GemCard.radius,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeleton(width: 96, height: 12, radius: 6),
                        const SizedBox(height: 12),
                        _skeleton(width: double.infinity, height: 16, radius: 6),
                        const SizedBox(height: 10),
                        _skeleton(width: 140, height: 12, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ───────── error card ─────────

  Widget _errorCard() => _cardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Couldn't load gems",
                    style: GoogleFonts.fredoka(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.sheetInk,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              style: GoogleFonts.fredoka(
                fontSize: 13,
                color: AppTheme.sheetSubInk,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Retry',
                  style: GoogleFonts.fredoka(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  // ───────── shared pieces ─────────

  /// White card matching the GemCard surface/border/shadow so the loading and
  /// live states read as the same material.
  Widget _cardShell({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.sheetSurface,
          borderRadius: BorderRadius.circular(GemCard.radius),
          border: Border.all(color: AppTheme.sheetBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );

  /// A single shimmering placeholder block whose sweep is driven by [_shimmer].
  Widget _skeleton({
    required double width,
    required double height,
    required double radius,
  }) =>
      AnimatedBuilder(
        animation: _shimmer,
        builder: (_, __) {
          final t = _shimmer.value;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * (1 - t), 0),
                end: Alignment(1 - 2 * (1 - t), 0),
                colors: const [
                  Color(0xFFEDEDED),
                  Color(0xFFF7F7F7),
                  Color(0xFFEDEDED),
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      );
}

/// Faint orange dot-grid behind the loading state — gives the near-black canvas
/// brand texture without competing with the beacon or card.
class _DottedTexturePainter extends CustomPainter {
  const _DottedTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    const dot = 1.6;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dot, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DottedTexturePainter oldDelegate) => false;
}

/// The pulsing location beacon: a solid brand dot with one expanding, fading
/// ring. [t] is the controller's 0→1 progress, looped.
class _BeaconPainter extends CustomPainter {
  const _BeaconPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Beacon sits a little above the vertical centre so the bottom card never
    // crowds it.
    final centre = Offset(size.width / 2, size.height * 0.42);

    // Expanding ring: radius grows, opacity fades as it grows.
    final ringRadius = 14 + 46 * t;
    final ringAlpha = (1 - t).clamp(0.0, 1.0) * 0.5;
    canvas.drawCircle(
      centre,
      ringRadius,
      Paint()
        ..color = AppTheme.primary.withValues(alpha: ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Soft glow + solid core dot, matching the map's location marker.
    canvas.drawCircle(
      centre,
      16,
      Paint()..color = AppTheme.primary.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      centre,
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      centre,
      5,
      Paint()..color = AppTheme.primary,
    );
  }

  @override
  bool shouldRepaint(_BeaconPainter oldDelegate) => oldDelegate.t != t;
}

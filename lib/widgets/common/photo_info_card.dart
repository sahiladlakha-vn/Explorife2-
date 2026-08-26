import 'package:flutter/material.dart';
import '../app_network_image.dart';

/// The shared 225-wide photo-card shell used by Home's horizontal rails —
/// full-bleed image, bottom gradient scrim, rounded corners, optional
/// top-left/top-right overlays, and a bottom info block. Extracted so
/// Home's rails (Featured Gems, Explore Ideas) share one visual shell
/// instead of drifting into near-duplicate card widgets — see
/// _FeaturedGemCard and _CollectionCard in home_screen.dart, both built on
/// this.
class PhotoInfoCard extends StatelessWidget {
  const PhotoInfoCard({
    super.key,
    required this.imageUrl,
    required this.bottom,
    this.width = 225,
    this.height = 290,
    this.topLeft,
    this.topRight,
    this.onTap,
    this.semanticLabel,
  });

  final String imageUrl;
  final Widget bottom;
  final double width;
  final double height;
  final Widget? topLeft;
  final Widget? topRight;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(right: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppNetworkImage(url: imageUrl, fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            if (topLeft != null) Positioned(top: 12, left: 12, child: topLeft!),
            if (topRight != null) Positioned(top: 8, right: 8, child: topRight!),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: bottom,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

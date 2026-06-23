// lib/widgets/app_network_image.dart
//
// One image widget for the whole app. Wraps cached_network_image so every
// remote image gets:
//   • a shimmer placeholder while it loads (held still for reduced-motion users)
//   • a graceful fallback box if the URL is dead or the network drops
//   • correct accessibility semantics (decorative by default, labelled on demand)
//
// Replaces every raw `Image.network(...)` call. cached_network_image and
// shimmer are already in pubspec.yaml — no new dependencies.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme/app_theme.dart';

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// Provide for content-bearing images (e.g. a destination photo). Leave null
  /// for purely decorative images so screen readers skip them.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => ImageShimmer(width: width, height: height),
      errorWidget: (_, __, ___) => ImageFallback(width: width, height: height),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    if (semanticLabel == null) {
      // Decorative — keep it out of the accessibility tree.
      return ExcludeSemantics(child: image);
    }
    return Semantics(image: true, label: semanticLabel, child: image);
  }
}

/// Shimmering placeholder sized to the image slot. Falls back to a static
/// block when the user has reduced-motion enabled.
class ImageShimmer extends StatelessWidget {
  const ImageShimmer({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final block = Container(width: width, height: height, color: AppTheme.surface2);
    if (MediaQuery.of(context).disableAnimations) return block;

    return Shimmer.fromColors(
      baseColor: AppTheme.surface2,
      highlightColor: const Color(0xFF2C2C2C),
      child: block,
    );
  }
}

/// Shown when an image fails to load.
class ImageFallback extends StatelessWidget {
  const ImageFallback({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppTheme.surface2,
      alignment: Alignment.center,
      child: const Icon(Icons.terrain_rounded, color: AppTheme.textSecondary, size: 26),
    );
  }
}

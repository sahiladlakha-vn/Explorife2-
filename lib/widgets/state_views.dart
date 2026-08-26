// lib/widgets/state_views.dart
//
// Shared loading / error / empty views so every screen handles the four data
// states the same way. Copy is written in the interface's voice: it says what
// happened and what to do, and never apologises or goes vague.
//
// Uses the `shimmer` package already in pubspec.yaml. Reduced-motion safe.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// SKELETON PRIMITIVE
// ─────────────────────────────────────────────────────────────
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (MediaQuery.of(context).disableAnimations) return block;
    return Shimmer.fromColors(
      baseColor: AppTheme.lightCard,
      highlightColor: Colors.white,
      child: block,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FEATURED ROW SKELETON  (matches the 225×290 horizontal cards)
// ─────────────────────────────────────────────────────────────
class FeaturedRowSkeleton extends StatelessWidget {
  const FeaturedRowSkeleton({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading featured destinations',
      liveRegion: true,
      child: SizedBox(
        height: 290,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: count,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Skeleton(width: 225, height: 290, radius: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TRAIL LIST SKELETON  (matches the 72-high _TrailCard rows)
// ─────────────────────────────────────────────────────────────
class TrailListSkeleton extends StatelessWidget {
  const TrailListSkeleton({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading trails',
      liveRegion: true,
      child: Column(
        children: List.generate(
          count,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: const Row(
              children: [
                Skeleton(width: 72, height: 72, radius: 12),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 140, height: 14),
                      SizedBox(height: 8),
                      Skeleton(width: 90, height: 11),
                      SizedBox(height: 10),
                      Skeleton(width: 110, height: 18, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ERROR STATE
// ─────────────────────────────────────────────────────────────
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.onRetry,
    this.message,
  });

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36, color: AppTheme.lightMute),
            const SizedBox(height: 14),
            Text(
              "Couldn't load destinations",
              textAlign: TextAlign.center,
              style: GoogleFonts.bebasNeue(
                fontSize: 24,
                letterSpacing: 0.5,
                color: AppTheme.lightInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message ?? 'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute, height: 1.5),
            ),
            const SizedBox(height: 18),
            // Min 44-high tap target.
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.text,
    this.icon = Icons.travel_explore_rounded,
    this.onAction,
    this.actionLabel,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppTheme.lightMute),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute, height: 1.5),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

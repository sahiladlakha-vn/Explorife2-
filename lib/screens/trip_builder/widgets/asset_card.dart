import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../widgets/app_network_image.dart';
import '../asset_data.dart';

/// A draggable discovery gem. Drag it onto an itinerary time-slot (File 13's
/// `DragTarget<AssetData>`) to add it as a stop. Resting card + a lifted copy
/// under the pointer while dragging + a faded origin so the source is legible.
///
/// [showLocation] is normally false — the panel header already says
/// "Discover $location", so the subtitle stays lean (emoji + category) and the
/// card breathes at the 240px left-pane width. The panel flips it true only in
/// the location-fallback state, where the list is mixed locations and the row
/// needs annotating.
class AssetCard extends StatelessWidget {
  const AssetCard({super.key, required this.gem, this.showLocation = false});

  final Gem gem;
  final bool showLocation;

  AssetData get _payload =>
      AssetData(gemId: gem.id, displayName: gem.gemName);

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder so the drag feedback is the exact width of the origin card
    // — it reads as "the card lifted", not "a different card appeared".
    return LayoutBuilder(
      builder: (context, c) => Draggable<AssetData>(
        data: _payload,
        // Pointer-anchor: the feedback tracks the cursor rather than snapping the
        // card's top-left to it — right for a compact list → large canvas drop.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => HapticFeedback.lightImpact(),
        feedback: _DragFeedback(
            gem: gem, width: c.maxWidth, showLocation: showLocation),
        childWhenDragging:
            Opacity(opacity: 0.4, child: _CardBody(gem: gem, showLocation: showLocation)),
        child: _CardBody(gem: gem, showLocation: showLocation),
      ),
    );
  }
}

/// Resting (and origin) card body. No price chip — gems are free.
class _CardBody extends StatelessWidget {
  const _CardBody({required this.gem, required this.showLocation});

  final Gem gem;
  final bool showLocation;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = gem.photoUrl != null && gem.photoUrl!.isNotEmpty;
    final hasLoc = gem.gemLocation != null && gem.gemLocation!.isNotEmpty;
    final subtitle = showLocation && hasLoc
        ? '${gem.emoji} ${gem.displayCategory} · ${gem.gemLocation}'
        : '${gem.emoji} ${gem.displayCategory}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: hasPhoto
                  ? AppNetworkImage(url: gem.photoUrl!) // guarded: non-null above
                  : _EmojiFallback(gem: gem),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(gem.gemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.drag_indicator,
              color: AppTheme.textSecondary, size: 20),
        ],
      ),
    );
  }
}

/// Lifted copy shown under the pointer while dragging. Sized to [width] so it
/// matches the origin card exactly.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({
    required this.gem,
    required this.width,
    required this.showLocation,
  });

  final Gem gem;
  final double width;
  final bool showLocation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Transform.scale(
        scale: 0.95,
        child: SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54,
                    blurRadius: 16,
                    offset: Offset(0, 8)),
              ],
            ),
            child: _CardBody(gem: gem, showLocation: showLocation),
          ),
        ),
      ),
    );
  }
}

/// Category-emoji tile shown when a gem has no photo.
class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({required this.gem});

  final Gem gem;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface2,
      alignment: Alignment.center,
      child: Text(gem.emoji, style: const TextStyle(fontSize: 22)),
    );
  }
}

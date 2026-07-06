import 'package:flutter/widgets.dart';

/// A single marker to render on the map. Kept platform-agnostic so the same
/// data drives both the web (Mapbox GL globe) and native (flutter_map) engines.
class MapMarkerData {
  final String id;
  final double lat;
  final double lng;
  final String emoji;
  final IconData icon;

  /// When present, the marker shows this photo as a circular thumbnail
  /// instead of the category emoji/icon.
  final String? photoUrl;

  const MapMarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.emoji,
    required this.icon,
    this.photoUrl,
  });
}

/// A rectangular region (in CSS/logical pixels, measured from the map's
/// top-left) that a Flutter overlay occupies over the web map. The web engine
/// lays a transparent gesture shield over each of these so horizontal swipes on
/// the floating overlays (filter chips, card deck) can't bleed through to the
/// Mapbox canvas and pan the map. Platform-agnostic so the contract stays one
/// shape; native ignores it.
class MapShieldRect {
  final double top;
  final double left;
  final double width;
  final double height;
  const MapShieldRect({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });
}

/// Imperative handle the screen uses to drive the underlying map after it is
/// ready (zoom buttons, locate, fly-to, fit-bounds). Each engine supplies its
/// own implementation.
abstract class MapEngineController {
  void zoomBy(double delta);
  void flyTo(double lat, double lng, double zoom);

  /// Animates the camera to a gem at [lat]/[lng]/[zoom], offset UP in pixel
  /// space by [sheetExtentPx]/2 so the gem lands in the visible map slice
  /// *above* the bottom sheet instead of behind it. [sheetExtentPx] is the
  /// sheet's live height from the bottom edge (the single source of truth fed
  /// from the sheet controller's extent). The shift is done in projected pixel
  /// space, so it stays correct across zoom and latitude — never a fixed-degree
  /// latitude nudge.
  void focusGem(double lat, double lng, double zoom, double sheetExtentPx);

  void fitMarkers(List<MapMarkerData> markers);
  void locate();
  void setStyle(String styleId);
  void select(String id);

  /// Resets the camera orientation back to north-up (bearing 0) and removes any
  /// tilt (pitch 0), animating the transition. Drives the North Orientation
  /// control. On native (flutter_map) only bearing applies — there is no pitch.
  void resetNorth();

  /// Shows/hides a fixed centre "drop" pin painted inside the map's own
  /// compositing surface (web), so it stays glued to screen centre with zero
  /// lag during pan/rotate. No-op on engines that render inside the Flutter
  /// tree (native), where a Flutter overlay widget is used instead.
  void setCenterPin(bool show);

  /// Tells the engine that the bottom [coverPx] CSS pixels of the map are
  /// covered by the Flutter bottom sheet, so the web engine can lay a
  /// transparent gesture shield over that strip — stopping sheet drags/scrolls
  /// from bleeding into the Mapbox canvas underneath. Pass 0 to clear it.
  /// No-op on native, where the map is a Flutter widget and pointer routing is
  /// handled by the framework.
  void setSheetCoverage(double coverPx);

  /// Lays a transparent gesture shield over each of [rects] (CSS px from the
  /// map's top-left), so swipes on floating overlays above the map — the filter
  /// chip row and the card deck — are absorbed before reaching the Mapbox
  /// canvas. Passing an empty list clears all overlay shields. This is the same
  /// deterministic DOM-level backstop [setSheetCoverage] uses, extended to the
  /// overlays that aren't the bottom sheet. No-op on native.
  void setOverlayShields(List<MapShieldRect> rects);
}

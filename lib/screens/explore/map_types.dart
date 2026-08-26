import 'package:flutter/widgets.dart';

/// What a [MapMarkerData] visually renders as. `pin` is the default (and the
/// only kind Explore's gem markers ever use); `arrow`/`dayChip` back the trip
/// route map's direction indicators and per-day labels.
enum MapMarkerKind {
  /// Circular pin — emoji/icon/photo by default, or a numbered badge when
  /// [MapMarkerData.label] is set. Tappable.
  pin,

  /// Small rotated triangle showing travel direction along a route segment.
  /// Not tappable.
  arrow,

  /// Rounded pill label (e.g. "DAY 1"), placed along a day's route. Not
  /// tappable.
  dayChip,
}

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

  /// When present (and [kind] is [MapMarkerKind.pin]), the marker renders as
  /// a numbered/labeled pin instead of the emoji/icon/photo treatment — e.g.
  /// a trip itinerary's "1.2" stop label, or "DAY 1" for a [MapMarkerKind.dayChip].
  final String? label;

  final MapMarkerKind kind;

  /// Fill/accent color — a [pin]'s background, an [arrow]'s fill, or a
  /// [dayChip]'s pill background. Null keeps each kind's own default (green
  /// glow for a plain gem pin, dark for a plain numbered pin).
  final Color? color;

  /// Rotation in degrees (0 = pointing up/north), meaningful for
  /// [MapMarkerKind.arrow] only.
  final double? rotationDegrees;

  const MapMarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.emoji,
    required this.icon,
    this.photoUrl,
    this.label,
    this.kind = MapMarkerKind.pin,
    this.color,
    this.rotationDegrees,
  });
}

/// One day's route line, in its own color — the trip route map draws one of
/// these per day rather than a single flat multi-day line, so days stay
/// visually distinguishable even where routes cross.
class MapRouteSegment {
  final List<({double lat, double lng})> points;
  final Color color;
  const MapRouteSegment({required this.points, required this.color});
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

  /// Sets Mapbox Standard Style's time-of-day lighting — one of 'dawn' |
  /// 'day' | 'dusk' | 'night' (Mapbox's own preset names, via
  /// `map.setConfigProperty('basemap', 'lightPreset', ...)`). Only Standard
  /// has this concept; the web engine no-ops (catches the error) when a
  /// non-Standard style is active, and this is a full no-op on native
  /// (flutter_map has no Standard Style / lighting-engine equivalent at all —
  /// see map_engine_native.dart's header comment).
  void setLightPreset(String preset);

  /// Resets the camera orientation back to north-up (bearing 0) and removes any
  /// tilt (pitch 0), animating the transition. Drives the North Orientation
  /// control. On native (flutter_map) only bearing applies — there is no pitch.
  void resetNorth();

  /// Toggles a tilted 3D perspective (pitch 60°), revealing real mountain/
  /// valley terrain relief — vs. the flat top-down view (pitch 0°). Bearing
  /// is untouched, unlike [resetNorth]. The web engine registers Mapbox's
  /// terrain-DEM source ambiently, so relief is also visible via pinch/
  /// two-finger-drag tilt gestures, not just this toggle. No-op on native
  /// (flutter_map has no pitch or terrain support).
  void setTilted(bool tilted);

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

  /// Shows a small callout/tooltip anchored to the point at [lat]/[lng] —
  /// e.g. a tapped trip-route pin's stop name and day/time. Only one is ever
  /// shown at a time: calling this again replaces whatever callout is
  /// already open. Web uses Mapbox GL JS's native `Popup` (auto-anchored, so
  /// it flips to stay in view near an edge); native has no built-in
  /// equivalent in flutter_map, so it's a custom Flutter overlay positioned
  /// via the camera's own projection math.
  void showCallout(
      {required double lat,
      required double lng,
      required String title,
      String? subtitle});

  /// Hides the current callout, if any. No-op if none is showing.
  void hideCallout();
}

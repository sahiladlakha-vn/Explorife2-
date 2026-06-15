import 'package:flutter/widgets.dart';

/// A single marker to render on the map. Kept platform-agnostic so the same
/// data drives both the web (Mapbox GL globe) and native (flutter_map) engines.
class MapMarkerData {
  final String id;
  final double lat;
  final double lng;
  final String emoji;
  final IconData icon;

  const MapMarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.emoji,
    required this.icon,
  });
}

/// Imperative handle the screen uses to drive the underlying map after it is
/// ready (zoom buttons, locate, fly-to, fit-bounds). Each engine supplies its
/// own implementation.
abstract class MapEngineController {
  void zoomBy(double delta);
  void flyTo(double lat, double lng, double zoom);
  void fitMarkers(List<MapMarkerData> markers);
  void locate();
  void setStyle(String styleId);
  void select(String id);
}

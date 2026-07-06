// Native/non-web implementation of the map engine. Mapbox GL JS is unavailable
// off the web, so we fall back to flutter_map (flat Web-Mercator raster tiles)
// while exposing the exact same MapEngineView/MapEngineController API.
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_types.dart';

class _NativeController implements MapEngineController {
  final MapController controller;
  final void Function(List<MapMarkerData>) onFit;
  _NativeController(this.controller, this.onFit);

  @override
  void zoomBy(double delta) {
    final cam = controller.camera;
    controller.move(cam.center, (cam.zoom + delta).clamp(2, 18));
  }

  @override
  void flyTo(double lat, double lng, double zoom) {
    controller.move(LatLng(lat, lng), zoom);
  }

  @override
  void focusGem(double lat, double lng, double zoom, double sheetExtentPx) {
    final target = LatLng(lat, lng);
    if (sheetExtentPx <= 0) {
      controller.move(target, zoom);
      return;
    }
    // Work in world-pixel space at the TARGET zoom so the offset is correct
    // across zoom and latitude. Pushing the camera centre DOWN by sheetPx/2 in
    // pixels makes the gem appear that many pixels ABOVE screen centre — i.e.
    // inside the visible map slice above the sheet.
    final cam = controller.camera;
    final pt = cam.project(target, zoom);
    final newCenter = cam.unproject(
      Point(pt.x, pt.y + sheetExtentPx / 2),
      zoom,
    );
    controller.move(newCenter, zoom);
  }

  @override
  void fitMarkers(List<MapMarkerData> markers) => onFit(markers);

  @override
  void locate() {/* handled by the screen via geolocator */}

  @override
  void setStyle(String styleId) {/* style swap handled by the screen */}

  @override
  void select(String id) {/* selection handled by the screen */}

  @override
  void resetNorth() {
    // flutter_map has no pitch; rotating to 0 restores north-up.
    controller.rotate(0);
  }

  @override
  void setCenterPin(bool show) {/* native uses a Flutter overlay widget */}

  @override
  void setSheetCoverage(double coverPx) {/* no platform-view bleed on native */}

  @override
  void setOverlayShields(List<MapShieldRect> rects) {/* no platform-view bleed */}
}

class MapEngineView extends StatefulWidget {
  final List<MapMarkerData> markers;
  final String styleId;
  final String token;
  final ValueChanged<String> onMarkerTap;
  final ValueChanged<MapEngineController> onReady;

  /// Called whenever the camera moves, with the centre coordinate AND the
  /// current viewport bounds (west/south/east/north). The centre tracks the
  /// point under the fixed pin (placement mode); the bounds scope the floating
  /// deck to gems on screen. Bounds assume non-wrapping (W ≤ E).
  final void Function(double lat, double lng, double west, double south,
      double east, double north)? onCameraIdle;

  /// Called whenever the map rotates, with the current bearing in degrees.
  /// Drives the rotation-gated compass control.
  final ValueChanged<double>? onBearingChanged;

  /// Optional "you are here" location. When set, a blue dot is rendered at
  /// this coordinate.
  final double? userLat;
  final double? userLng;

  const MapEngineView({
    super.key,
    required this.markers,
    required this.styleId,
    required this.token,
    required this.onMarkerTap,
    required this.onReady,
    this.onCameraIdle,
    this.onBearingChanged,
    this.userLat,
    this.userLng,
  });

  @override
  State<MapEngineView> createState() => _MapEngineViewState();
}

class _MapEngineViewState extends State<MapEngineView> {
  final MapController _controller = MapController();

  String get _tileUrl {
    if (widget.token.isEmpty) {
      return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
    }
    return 'https://api.mapbox.com/styles/v1/mapbox/${widget.styleId}/tiles/256/{z}/{x}/{y}@2x?access_token=${widget.token}';
  }

  void _fit(List<MapMarkerData> markers) {
    if (markers.isEmpty) return;
    if (markers.length == 1) {
      _controller.move(LatLng(markers.first.lat, markers.first.lng), 12);
      return;
    }
    final pts = markers.map((m) => LatLng(m.lat, m.lng)).toList();
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(60, 120, 60, 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: const LatLng(16.0, 110.0),
        initialZoom: 3,
        minZoom: 2,
        maxZoom: 18,
        onMapReady: () =>
            widget.onReady(_NativeController(_controller, _fit)),
        onPositionChanged: (camera, _) {
          final c = camera.center;
          // visibleBounds: southWest = (south lat, west lng), northEast =
          // (north lat, east lng). Same W/S/E/N convention the web engine emits
          // from getBounds(); assumes non-wrapping bounds (W ≤ E).
          final b = _controller.camera.visibleBounds;
          if (c != null) {
            widget.onCameraIdle?.call(
              c.latitude,
              c.longitude,
              b.southWest.longitude,
              b.southWest.latitude,
              b.northEast.longitude,
              b.northEast.latitude,
            );
          }
          // MapPosition carries no bearing; read it from the live camera, which
          // exposes rotation in degrees.
          widget.onBearingChanged?.call(_controller.camera.rotation);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.explorife.app',
          tileSize: 256,
        ),
        MarkerLayer(
          markers: [
            ...widget.markers.map((m) => Marker(
                  point: LatLng(m.lat, m.lng),
                  width: 46,
                  height: 46,
                  child: GestureDetector(
                    onTap: () => widget.onMarkerTap(m.id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF14E08A), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        image: m.photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(m.photoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: m.photoUrl != null
                          ? null
                          : Icon(m.icon,
                              size: 20, color: const Color(0xFF14E08A)),
                    ),
                  ),
                )),
            if (widget.userLat != null && widget.userLng != null)
              Marker(
                point: LatLng(widget.userLat!, widget.userLng!),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A8CFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A8CFF).withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

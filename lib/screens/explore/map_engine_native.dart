// Native/non-web implementation of the map engine. Mapbox GL JS is unavailable
// off the web, so we fall back to flutter_map (flat Web-Mercator raster tiles)
// while exposing the exact same MapEngineView/MapEngineController API.
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
  void fitMarkers(List<MapMarkerData> markers) => onFit(markers);

  @override
  void locate() {/* handled by the screen via geolocator */}

  @override
  void setStyle(String styleId) {/* style swap handled by the screen */}

  @override
  void select(String id) {/* selection handled by the screen */}
}

class MapEngineView extends StatefulWidget {
  final List<MapMarkerData> markers;
  final String styleId;
  final String token;
  final ValueChanged<String> onMarkerTap;
  final ValueChanged<MapEngineController> onReady;

  const MapEngineView({
    super.key,
    required this.markers,
    required this.styleId,
    required this.token,
    required this.onMarkerTap,
    required this.onReady,
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
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.explorife.app',
          tileSize: 256,
        ),
        MarkerLayer(
          markers: widget.markers
              .map((m) => Marker(
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
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(m.icon,
                            size: 20, color: const Color(0xFF14E08A)),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

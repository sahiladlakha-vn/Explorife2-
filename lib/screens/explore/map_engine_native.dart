// Native/non-web implementation of the map engine. Mapbox GL JS is unavailable
// off the web, so we fall back to flutter_map (flat Web-Mercator raster tiles)
// while exposing the exact same MapEngineView/MapEngineController API.
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// hide Path: latlong2 exports its own generic Path<T> (a geo route path),
// which otherwise shadows dart:ui's Path that _TailPainter's CustomPainter
// needs for the callout bubble's pointed tail.
import 'package:latlong2/latlong.dart' hide Path;

import 'map_types.dart';

typedef _ShowCalloutFn = void Function(
    {required double lat,
    required double lng,
    required String title,
    String? subtitle});

class _NativeController implements MapEngineController {
  final MapController controller;
  final void Function(List<MapMarkerData>) onFit;
  final _ShowCalloutFn onShowCallout;
  final VoidCallback onHideCallout;
  _NativeController(
      this.controller, this.onFit, this.onShowCallout, this.onHideCallout);

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
  void setLightPreset(String preset) {
    /* flutter_map has no Standard Style / lighting engine */
  }

  @override
  void select(String id) {/* selection handled by the screen */}

  @override
  void resetNorth() {
    // flutter_map has no pitch; rotating to 0 restores north-up.
    controller.rotate(0);
  }

  @override
  void setTilted(bool tilted) {/* flutter_map has no pitch/terrain support */}

  @override
  void setCenterPin(bool show) {/* native uses a Flutter overlay widget */}

  @override
  void setSheetCoverage(double coverPx) {/* no platform-view bleed on native */}

  @override
  void setOverlayShields(List<MapShieldRect> rects) {
    /* no platform-view bleed */
  }

  @override
  void showCallout(
          {required double lat,
          required double lng,
          required String title,
          String? subtitle}) =>
      onShowCallout(lat: lat, lng: lng, title: title, subtitle: subtitle);

  @override
  void hideCallout() => onHideCallout();
}

class MapEngineView extends StatefulWidget {
  final List<MapMarkerData> markers;
  final String styleId;
  final String token;
  final ValueChanged<String> onMarkerTap;
  final ValueChanged<MapEngineController> onReady;

  /// Accepted for API parity with the web engine; unused here — flutter_map
  /// has no Standard Style / dynamic-lighting equivalent (see this file's
  /// header comment on why native can't render Standard Style at all).
  final String lightPreset;

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

  /// One colored connecting line per day, drawn under the markers — e.g. a
  /// trip's itinerary route. A segment with fewer than 2 points draws
  /// nothing (a line needs at least two ends); null/empty draws no lines.
  final List<MapRouteSegment>? routes;

  /// Called whenever the current callout ([MapEngineController.showCallout])
  /// closes for a reason the caller didn't directly initiate — e.g. the user
  /// tapped empty map space. Lets the caller keep its own "which marker is
  /// selected" state in sync without guessing.
  final VoidCallback? onCalloutClosed;

  const MapEngineView({
    super.key,
    required this.markers,
    required this.styleId,
    required this.token,
    required this.onMarkerTap,
    required this.onReady,
    this.lightPreset = 'day',
    this.onCameraIdle,
    this.onBearingChanged,
    this.userLat,
    this.userLng,
    this.routes,
    this.onCalloutClosed,
  });

  @override
  State<MapEngineView> createState() => _MapEngineViewState();
}

class _MapEngineViewState extends State<MapEngineView> {
  final MapController _controller = MapController();

  ({double lat, double lng, String title, String? subtitle})? _callout;

  void _showCallout(
      {required double lat,
      required double lng,
      required String title,
      String? subtitle}) {
    setState(() =>
        _callout = (lat: lat, lng: lng, title: title, subtitle: subtitle));
  }

  void _hideCallout({bool notify = false}) {
    if (_callout == null) return;
    setState(() => _callout = null);
    if (notify) widget.onCalloutClosed?.call();
  }

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
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          _buildMap(constraints.biggest),
          if (_callout != null) _buildCalloutOverlay(constraints.biggest),
        ],
      ),
    );
  }

  Widget _buildMap(Size size) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: const LatLng(16.0, 110.0),
        initialZoom: 3,
        minZoom: 2,
        maxZoom: 18,
        onMapReady: () => widget.onReady(_NativeController(
            _controller, _fit, _showCallout, () => _hideCallout())),
        // Tapping empty map space (not a marker) dismisses any open callout
        // — flutter_map has no separate "background tap" vs "marker tap"
        // routing, so this only fires when the tap didn't land on a Marker's
        // own GestureDetector (those consume the gesture first).
        onTap: (_, __) => _hideCallout(notify: true),
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
          // Keep the callout glued to its marker while panning/zooming —
          // its screen position is derived from the camera below, so it
          // needs a rebuild on every camera change, not just on open/close.
          if (_callout != null) setState(() {});
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.explorife.app',
          tileSize: 256,
        ),
        if (widget.routes != null && widget.routes!.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final seg in widget.routes!)
                if (seg.points.length >= 2)
                  Polyline(
                    points: [
                      for (final p in seg.points) LatLng(p.lat, p.lng),
                    ],
                    strokeWidth: 3,
                    color: seg.color,
                  ),
            ],
          ),
        MarkerLayer(
          markers: [
            ...widget.markers.map((m) {
              final size = _markerSize(m);
              // The teardrop photo-pin's visual tip sits at the bottom of its
              // box (not the center, unlike every other marker kind here) —
              // bottomCenter alignment is what keeps that tip pointing at the
              // actual coordinate instead of floating above/beside it.
              final isPhotoPin = m.kind == MapMarkerKind.pin && m.label == null;
              return Marker(
                point: LatLng(m.lat, m.lng),
                width: size.width,
                height: size.height,
                alignment:
                    isPhotoPin ? Alignment.bottomCenter : Alignment.center,
                child: GestureDetector(
                  onTap: () => widget.onMarkerTap(m.id),
                  child: _buildMarker(m),
                ),
              );
            }),
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

  /// Positions the callout bubble relative to its marker using the camera's
  /// own projection math (same technique [focusGem] already uses): the
  /// marker's on-screen offset from the map's centre, in pixels, is
  /// `project(marker) - project(cameraCenter)` at the current zoom — added
  /// to the widget's own centre (from [size], via the enclosing
  /// LayoutBuilder) gives its actual screen position. Flips below the
  /// marker instead of above if the bubble would clip the top edge.
  Widget _buildCalloutOverlay(Size size) {
    final callout = _callout!;
    final cam = _controller.camera;
    final centerPx = cam.project(cam.center, cam.zoom);
    final targetPx = cam.project(LatLng(callout.lat, callout.lng), cam.zoom);
    final markerX = size.width / 2 + (targetPx.x - centerPx.x);
    final markerY = size.height / 2 + (targetPx.y - centerPx.y);

    const bubbleWidth = 220.0;
    const bubbleGap = 14.0; // clearance from the marker itself
    const estimatedBubbleHeight = 56.0;
    final pointsDown = markerY - estimatedBubbleHeight - bubbleGap >= 0;
    final top = pointsDown
        ? markerY - estimatedBubbleHeight - bubbleGap
        : markerY + bubbleGap;
    final left =
        (markerX - bubbleWidth / 2).clamp(8.0, size.width - bubbleWidth - 8);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: _CalloutBubble(
          width: bubbleWidth,
          title: callout.title,
          subtitle: callout.subtitle,
          pointDown: pointsDown,
        ),
      ),
    );
  }

  Size _markerSize(MapMarkerData m) => switch (m.kind) {
        MapMarkerKind.arrow => const Size(20, 20),
        MapMarkerKind.dayChip => const Size(72, 26),
        // Numbered itinerary-stop pins stay the plain circle (sequence
        // legibility matters more there than a photo — see PhotoPinMarker's
        // doc comment); only the unlabeled gem-browsing pin becomes the
        // taller teardrop shape, with room for its pointed tail below the
        // circular head.
        MapMarkerKind.pin =>
          m.label != null ? const Size(46, 46) : const Size(42, 54),
      };

  Widget _buildMarker(MapMarkerData m) {
    switch (m.kind) {
      case MapMarkerKind.arrow:
        return Transform.rotate(
          angle: (m.rotationDegrees ?? 0) * 3.1415926535 / 180,
          child: Icon(Icons.arrow_upward,
              size: 18, color: m.color ?? const Color(0xFF6B4A3A)),
        );
      case MapMarkerKind.dayChip:
        return Container(
          decoration: BoxDecoration(
            color: m.color ?? const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            m.label ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        );
      case MapMarkerKind.pin:
        if (m.label != null) {
          return Container(
            decoration: BoxDecoration(
              color: m.color ?? const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              m.label!,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          );
        }
        return PhotoPinMarker(photoUrl: m.photoUrl, icon: m.icon);
    }
  }
}

/// The teardrop, gradient-bordered "photo pin" used for plain gem-browsing
/// markers (Explore/Discovery map only — itinerary/trip-route stops keep the
/// simpler numbered circle above, since sequence legibility matters more
/// there than a photo). A circular head — [photoUrl]'s image cropped inside
/// when present, else a plain icon on a light fill — merges into a pointed
/// tail via a rotated square peeking out from behind/below it, the standard
/// cheap way to fake a pin silhouette without hand-rolled bezier math.
class PhotoPinMarker extends StatelessWidget {
  final String? photoUrl;
  final IconData icon;
  const PhotoPinMarker({super.key, required this.photoUrl, required this.icon});

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A00), Color(0xFFFFC542)],
  );
  static const _headDiameter = 40.0;
  static const _tailSize = 14.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 54,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Tail: a 45°-rotated square, positioned so only its bottom
          // corner peeks out below the head circle drawn on top of it.
          Positioned(
            top: _headDiameter - 10,
            child: Transform.rotate(
              angle: 0.785398, // pi / 4
              child: Container(
                width: _tailSize,
                height: _tailSize,
                decoration: const BoxDecoration(gradient: _gradient),
              ),
            ),
          ),
          // Head: gradient ring -> thin white gap -> circular photo/icon.
          Container(
            width: _headDiameter,
            height: _headDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _gradient,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: photoUrl != null
                      ? Image.network(photoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFFFFF3E0),
                          alignment: Alignment.center,
                          child: Icon(icon,
                              size: 16, color: const Color(0xFFFF8A00)),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded callout with a small pointed tail toward its marker —
/// native's hand-built equivalent of web's Mapbox GL `Popup` (which renders
/// this same look via its own default styling instead). [pointDown] is true
/// when the bubble sits above the marker (tail on the bottom edge pointing
/// down at it); false when flipped below (tail on top, pointing up).
class _CalloutBubble extends StatelessWidget {
  const _CalloutBubble({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.pointDown,
  });

  final double width;
  final String title;
  final String? subtitle;
  final bool pointDown;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Color(0xFF6B6B6B), fontSize: 11.5)),
          ],
        ],
      ),
    );
    final tail =
        CustomPaint(size: const Size(14, 7), painter: _TailPainter(pointDown));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: pointDown ? [bubble, tail] : [tail, bubble],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.pointDown);
  final bool pointDown;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path();
    if (pointDown) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TailPainter oldDelegate) =>
      oldDelegate.pointDown != pointDown;
}

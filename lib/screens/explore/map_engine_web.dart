// Web implementation of the map engine: embeds Mapbox GL JS with
// `projection: 'globe'` inside a Flutter platform view. The actual map logic
// lives in web/mapbox_globe.js; here we register a <div> host per instance and
// call the global bridge functions via dart:js_interop.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'map_types.dart';

// ── JS bridge externs (must match window.explorife* in mapbox_globe.js) ──
@JS('explorifeMapInit')
external void _mapInit(
    web.HTMLElement el, JSString token, JSString style, JSFunction onTap);

@JS('explorifeMapSetGems')
external void _mapSetGems(web.HTMLElement el, JSString gemsJson);

@JS('explorifeMapSelect')
external void _mapSelect(web.HTMLElement el, JSString id);

@JS('explorifeMapZoom')
external void _mapZoom(web.HTMLElement el, JSNumber delta);

@JS('explorifeMapSetStyle')
external void _mapSetStyle(web.HTMLElement el, JSString style);

@JS('explorifeMapFlyTo')
external void _mapFlyTo(
    web.HTMLElement el, JSNumber lat, JSNumber lng, JSNumber zoom);

@JS('explorifeMapFocusGem')
external void _mapFocusGem(web.HTMLElement el, JSNumber lat, JSNumber lng,
    JSNumber zoom, JSNumber sheetPx);

@JS('explorifeMapFitGems')
external void _mapFitGems(web.HTMLElement el, JSString gemsJson);

@JS('explorifeMapSetRoute')
external void _mapSetRoute(web.HTMLElement el, JSString routeJson);

@JS('explorifeMapShowCallout')
external void _mapShowCallout(web.HTMLElement el, JSNumber lat, JSNumber lng,
    JSString title, JSString subtitle);

@JS('explorifeMapHideCallout')
external void _mapHideCallout(web.HTMLElement el);

@JS('explorifeMapOnCalloutClose')
external void _mapOnCalloutClose(web.HTMLElement el, JSFunction onClose);

@JS('explorifeMapLocate')
external void _mapLocate(web.HTMLElement el);

@JS('explorifeMapOnIdle')
external void _mapOnIdle(web.HTMLElement el, JSFunction onIdle);

@JS('explorifeMapSetCenterPin')
external void _mapSetCenterPin(web.HTMLElement el, JSBoolean show);

@JS('explorifeMapSetShield')
external void _mapSetShield(web.HTMLElement el, JSNumber coverPx);

@JS('explorifeMapSetOverlayShields')
external void _mapSetOverlayShields(web.HTMLElement el, JSString rectsJson);

@JS('explorifeMapSetUserLocation')
external void _mapSetUserLocation(
    web.HTMLElement el, JSNumber lat, JSNumber lng);

@JS('explorifeMapResetNorth')
external void _mapResetNorth(web.HTMLElement el);

@JS('explorifeMapOnRotate')
external void _mapOnRotate(web.HTMLElement el, JSFunction onRotate);

int _viewSeq = 0;

String _colorHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

String _markersJson(List<MapMarkerData> markers) {
  return jsonEncode(markers
      .map((m) => {
            'id': m.id,
            'lat': m.lat,
            'lng': m.lng,
            'emoji': m.emoji,
            'photo': m.photoUrl,
            'label': m.label,
            'kind': m.kind.name,
            'color': m.color != null ? _colorHex(m.color!) : null,
            'rotation': m.rotationDegrees,
          })
      .toList());
}

/// One entry per day's route segment — `window.explorifeMapSetRoute`
/// (mapbox_globe.js) turns this into one GeoJSON LineString feature per
/// entry, each carrying its own `color` so days stay visually distinct even
/// where routes cross.
String _routesJson(List<MapRouteSegment>? routes) {
  if (routes == null) return '[]';
  return jsonEncode([
    for (final seg in routes)
      if (seg.points.length >= 2)
        {
          'color': _colorHex(seg.color),
          'points': seg.points.map((p) => {'lat': p.lat, 'lng': p.lng}).toList(),
        },
  ]);
}

class _WebController implements MapEngineController {
  final web.HTMLElement el;
  _WebController(this.el);

  @override
  void zoomBy(double delta) => _mapZoom(el, delta.toJS);

  @override
  void flyTo(double lat, double lng, double zoom) =>
      _mapFlyTo(el, lat.toJS, lng.toJS, zoom.toJS);

  @override
  void focusGem(double lat, double lng, double zoom, double sheetExtentPx) =>
      _mapFocusGem(el, lat.toJS, lng.toJS, zoom.toJS, sheetExtentPx.toJS);

  @override
  void fitMarkers(List<MapMarkerData> markers) =>
      _mapFitGems(el, _markersJson(markers).toJS);

  @override
  void locate() => _mapLocate(el);

  @override
  void setStyle(String styleId) => _mapSetStyle(el, styleId.toJS);

  @override
  void select(String id) => _mapSelect(el, id.toJS);

  @override
  void setCenterPin(bool show) => _mapSetCenterPin(el, show.toJS);

  @override
  void setSheetCoverage(double coverPx) => _mapSetShield(el, coverPx.toJS);

  @override
  void setOverlayShields(List<MapShieldRect> rects) {
    final json = jsonEncode(rects
        .map((r) => {
              'top': r.top,
              'left': r.left,
              'width': r.width,
              'height': r.height,
            })
        .toList());
    _mapSetOverlayShields(el, json.toJS);
  }

  @override
  void resetNorth() => _mapResetNorth(el);

  @override
  void showCallout(
          {required double lat,
          required double lng,
          required String title,
          String? subtitle}) =>
      _mapShowCallout(el, lat.toJS, lng.toJS, title.toJS, (subtitle ?? '').toJS);

  @override
  void hideCallout() => _mapHideCallout(el);
}

class MapEngineView extends StatefulWidget {
  final List<MapMarkerData> markers;
  final String styleId;
  final String token;
  final ValueChanged<String> onMarkerTap;
  final ValueChanged<MapEngineController> onReady;

  /// Called whenever the camera comes to rest, with the centre coordinate AND
  /// the current viewport bounds (west/south/east/north). The centre tracks the
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
  /// nothing; null/empty draws no lines.
  final List<MapRouteSegment>? routes;

  /// Called whenever the current callout ([MapEngineController.showCallout])
  /// closes for a reason the caller didn't directly initiate — e.g. the user
  /// tapped empty map space (Mapbox's Popup `closeOnClick`). Lets the caller
  /// keep its own "which marker is selected" state in sync without guessing.
  final VoidCallback? onCalloutClosed;

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
    this.routes,
    this.onCalloutClosed,
  });

  @override
  State<MapEngineView> createState() => _MapEngineViewState();
}

class _MapEngineViewState extends State<MapEngineView> {
  late final String _viewType;
  late final web.HTMLElement _host;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'explorife-map-${_viewSeq++}';
    _host = (web.document.createElement('div') as web.HTMLElement)
      ..style.width = '100%'
      ..style.height = '100%';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _host);
  }

  void _initMap() {
    if (_initialised) return;
    _initialised = true;
    final onTap =
        ((JSString id) => widget.onMarkerTap(id.toDart)).toJS;
    _mapInit(_host, widget.token.toJS, widget.styleId.toJS, onTap);
    _pushMarkers();
    if (widget.onCameraIdle != null) {
      final onIdle = ((JSNumber lat, JSNumber lng, JSNumber west, JSNumber south,
              JSNumber east, JSNumber north) =>
          widget.onCameraIdle!(lat.toDartDouble, lng.toDartDouble,
              west.toDartDouble, south.toDartDouble, east.toDartDouble,
              north.toDartDouble)).toJS;
      _mapOnIdle(_host, onIdle);
    }
    if (widget.onBearingChanged != null) {
      final onRotate =
          ((JSNumber bearing) => widget.onBearingChanged!(bearing.toDartDouble))
              .toJS;
      _mapOnRotate(_host, onRotate);
    }
    if (widget.onCalloutClosed != null) {
      _mapOnCalloutClose(_host, (() => widget.onCalloutClosed!()).toJS);
    }
    widget.onReady(_WebController(_host));
    _pushUserLocation();
    _pushRoute();
  }

  void _pushMarkers() {
    _mapSetGems(_host, _markersJson(widget.markers).toJS);
  }

  void _pushRoute() {
    _mapSetRoute(_host, _routesJson(widget.routes).toJS);
  }

  void _pushUserLocation() {
    if (widget.userLat != null && widget.userLng != null) {
      _mapSetUserLocation(_host, widget.userLat!.toJS, widget.userLng!.toJS);
    }
  }

  @override
  void didUpdateWidget(covariant MapEngineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initialised) return;
    if (oldWidget.styleId != widget.styleId) {
      _mapSetStyle(_host, widget.styleId.toJS);
    }
    if (!_sameMarkers(oldWidget.markers, widget.markers)) {
      _pushMarkers();
    }
    if (oldWidget.userLat != widget.userLat ||
        oldWidget.userLng != widget.userLng) {
      _pushUserLocation();
    }
    if (!_sameRoutes(oldWidget.routes, widget.routes)) {
      _pushRoute();
    }
  }

  bool _sameMarkers(List<MapMarkerData> a, List<MapMarkerData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng ||
          a[i].label != b[i].label ||
          a[i].kind != b[i].kind ||
          a[i].color != b[i].color ||
          a[i].rotationDegrees != b[i].rotationDegrees) {
        return false;
      }
    }
    return true;
  }

  bool _sameRoutes(List<MapRouteSegment>? a, List<MapRouteSegment>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].color != b[i].color || a[i].points.length != b[i].points.length) {
        return false;
      }
      for (var j = 0; j < a[i].points.length; j++) {
        if (a[i].points[j].lat != b[i].points[j].lat ||
            a[i].points[j].lng != b[i].points[j].lng) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: _viewType,
      onPlatformViewCreated: (_) {
        // The host div is now attached; safe to boot Mapbox.
        WidgetsBinding.instance.addPostFrameCallback((_) => _initMap());
      },
    );
  }
}

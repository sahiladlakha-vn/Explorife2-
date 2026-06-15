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

@JS('explorifeMapFitGems')
external void _mapFitGems(web.HTMLElement el, JSString gemsJson);

@JS('explorifeMapLocate')
external void _mapLocate(web.HTMLElement el);

int _viewSeq = 0;

String _markersJson(List<MapMarkerData> markers) {
  return jsonEncode(markers
      .map((m) => {
            'id': m.id,
            'lat': m.lat,
            'lng': m.lng,
            'emoji': m.emoji,
          })
      .toList());
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
  void fitMarkers(List<MapMarkerData> markers) =>
      _mapFitGems(el, _markersJson(markers).toJS);

  @override
  void locate() => _mapLocate(el);

  @override
  void setStyle(String styleId) => _mapSetStyle(el, styleId.toJS);

  @override
  void select(String id) => _mapSelect(el, id.toJS);
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
    widget.onReady(_WebController(_host));
  }

  void _pushMarkers() {
    _mapSetGems(_host, _markersJson(widget.markers).toJS);
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
  }

  bool _sameMarkers(List<MapMarkerData> a, List<MapMarkerData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng) {
        return false;
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

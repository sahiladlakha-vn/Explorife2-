// Single import point for the explore screen. On web this resolves to the
// Mapbox GL JS globe engine; on native (dart:io present) it falls back to the
// flutter_map raster engine. Both expose MapEngineView + MapEngineController.
export 'map_types.dart';
export 'map_engine_web.dart' if (dart.library.io) 'map_engine_native.dart';

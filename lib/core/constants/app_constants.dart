import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'ExplorIfe';

  /// Single source of truth for the discovery-feed radius. The feed is NOT yet
  /// filtered to this radius (it filters by category only), so the sheet header
  /// uses "nearby" copy — leave this ready for viewport-distance wiring later.
  static const double feedRadiusKm = 5;

  // Placeholder image base URL (using picsum for demo)
  static const String imageBase = 'https://picsum.photos';

  static const List<String> categories = [
    'All',
    'Beach',
    'Mountains',
    'City',
    'Jungle',
    'Desert',
    'Cultural',
    'Adventure',
  ];

  // Parallel to [categories]. Material glyphs render from the bundled icon
  // font — unlike emoji, which CanvasKit can't reliably draw on web.
  static const List<IconData> categoryIcons = [
    Icons.public,
    Icons.beach_access,
    Icons.terrain,
    Icons.location_city,
    Icons.forest,
    Icons.wb_sunny,
    Icons.account_balance,
    Icons.hiking,
  ];
}

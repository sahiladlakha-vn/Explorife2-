import 'package:flutter/material.dart';

import '../../models/gem.dart';

/// Single source of truth for the gem category taxonomy's UI glyphs.
///
/// The canonical category keys and emoji live on [Gem] (pure-Dart model, kept
/// free of Flutter imports so it stays unit-testable). The Material icon per
/// category lives here in the UI layer because [IconData] is a Flutter type.
///
/// Material glyphs are used rather than emoji because CanvasKit can't reliably
/// render emoji on web. Previously this map was copy-pasted into the explore
/// map, the drop-gem form, and the placement map; centralizing it keeps every
/// surface rendering the same glyph per category.
class GemCategories {
  const GemCategories._();

  /// Keyed by the same category strings as [Gem.categories].
  static const Map<String, IconData> icons = {
    'hiking': Icons.hiking,
    'camping': Icons.cabin,
    'viewpoint': Icons.photo_camera,
    'food': Icons.restaurant,
    'temple': Icons.account_balance,
    'cave': Icons.landscape,
    'coastal': Icons.water,
    'nature': Icons.park,
    'heritage': Icons.museum,
    'landmark': Icons.filter_hdr,
  };

  /// Icon for [category], falling back to a generic pin for unknown/null values.
  static IconData iconFor(String? category) => icons[category] ?? Icons.place;
}

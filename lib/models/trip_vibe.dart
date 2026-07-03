import 'package:flutter/material.dart';

/// The trip's overall mood, chosen in Setup Step 1. Stored in `trips.vibe`
/// using the enum's [name] (e.g. 'slow'), so the column round-trips cleanly.
///
/// Labels and taglines live here (not in the widgets) because the same strings
/// surface in three places: the Step 1 vibe cards, the profile metadata line,
/// and the trip card subtitle. One source of copy avoids drift.
///
/// Icons map to the closest Material glyphs — the v2 spec named Tabler icons
/// (`ti-flower`, `ti-mountain`, `ti-tools-kitchen-2`, `ti-heart`) from the HTML
/// prototype, but adding an icon package for four glyphs isn't in scope.
enum TripVibe {
  slow(
    label: 'Slow and immersive',
    tagline: 'Local culture, long meals, depth over breadth.',
    icon: Icons.local_florist,
  ),
  fast(
    label: 'Fast-paced adventure',
    tagline: 'Hikes, surf, road trips. You\'ll sleep when you get home.',
    icon: Icons.terrain,
  ),
  foodie(
    label: 'Foodie pilgrimage',
    tagline: 'Street stalls, hidden kitchens, late-night noodles.',
    icon: Icons.restaurant_menu,
  ),
  romance(
    label: 'Romantic retreat',
    tagline: 'Quiet luxury, slow days, just the two of you.',
    icon: Icons.favorite_border,
  );

  const TripVibe({
    required this.label,
    required this.tagline,
    required this.icon,
  });

  /// Short UI label (vibe cards, subtitles, metadata line).
  final String label;

  /// One-line description shown under the label on Step 1's vibe cards.
  final String tagline;

  /// Material glyph for chips/badges.
  final IconData icon;

  /// Storage key persisted to `trips.vibe`.
  String get key => name;

  /// Resolves a persisted key back to a vibe. Returns null for null/unknown
  /// keys — legacy trips have no vibe set, so this must not throw.
  static TripVibe? fromKey(String? key) {
    if (key == null) return null;
    for (final v in TripVibe.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

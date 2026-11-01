/// Home's "EXPLORE IDEAS" rail — a real, Supabase-backed content type
/// (public.curated_collections) as of 2026-09-18, replacing what used to be
/// a hardcoded static Dart list (lib/core/constants/curated_collections.dart,
/// now removed). See the migration's own doc comment
/// (supabase/migrations/20260918000200_create_curated_collections.sql) for
/// the full reasoning — same "curated, publicly readable, no owner column"
/// shape as [Tour].
///
/// Each [CuratedCollection] scopes to exactly one of two things — a single
/// destination or a single Gem category — deliberately not a multi-city
/// "set" (e.g. "all of Vietnam"): the Destinations tab only matches a
/// search query against individual curated city names, not country names.
class CollectionScope {
  final bool isDestination;

  /// Destination scope: a city name (resolved to real coordinates via
  /// GeocodingService on tap, same as every other city-tap flow in this
  /// app). Category scope: one of Gem.categories, or 'all'.
  final String value;

  const CollectionScope.destination(this.value) : isDestination = true;
  const CollectionScope.category(this.value) : isDestination = false;
}

class CuratedCollection {
  final String id;
  final String title;
  final String subtitle;
  final String coverImageUrl;
  final CollectionScope scope;

  /// Curator-assigned, NOT an aggregated user/review score — this app has
  /// no review or booking backend to source a real rating from (same reason
  /// [Tour] itself has no rating field). Destination-scope only by
  /// convention (not DB-enforced) — a category collection like "Hiking
  /// Trails" isn't a place, so rating it doesn't make sense; left null there.
  final double? rating;

  /// Curator-written seasonal travel advice for the destination (e.g.
  /// "Oct–Dec"). Destination-scope only, same reasoning as [rating].
  final String? bestTimeToVisit;

  const CuratedCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.scope,
    this.rating,
    this.bestTimeToVisit,
  });

  factory CuratedCollection.fromJson(Map<String, dynamic> json) {
    final isDestination = json['is_destination'] as bool? ?? true;
    final scopeValue = json['scope_value'] as String? ?? '';
    return CuratedCollection(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String? ?? '',
      scope: isDestination
          ? CollectionScope.destination(scopeValue)
          : CollectionScope.category(scopeValue),
      rating: (json['rating'] as num?)?.toDouble(),
      bestTimeToVisit: json['best_time_to_visit'] as String?,
    );
  }
}

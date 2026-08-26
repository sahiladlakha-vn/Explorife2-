/// Editorial "Explore Ideas" content for Home's curated collections rail —
/// the CTA that replaced Start Exploring / DestinationBrowserSheet (Phase 2
/// of the unified search funnel). Same rationale as curated_destinations.dart
/// (which this data draws its destination-scoped photos/cities from): no
/// CMS or admin screen exists anywhere in this app, so hand-curated content
/// is a maintained Dart list — same pattern, same place any future curated
/// content should live rather than inventing a second mechanism.
///
/// DRAFT CONTENT — titles, subtitles, and cover photos below are real
/// (drawn from curated_destinations.dart's own real cities/photos, not
/// placeholder/lorem text), but have not been confirmed by a content owner
/// for real-user visibility yet. Per this phase's own constraint ("don't
/// ship placeholder content to real users"), get explicit sign-off on copy
/// and cover images before this collection set goes live.
///
/// Each [CuratedCollection] scopes to exactly one of two things — a single
/// destination or a single Gem category — deliberately not a multi-city
/// "set" (e.g. "all of Vietnam"): Phase 1's Destinations tab only matches a
/// search query against individual curated city names, not country names,
/// and this phase is scoped to not touch that matching logic. A
/// multi-destination collection type can be added later if that matcher is
/// extended to also match on country name.
class CollectionScope {
  final bool isDestination;

  /// Destination scope: a city name from curated_destinations.dart (resolved
  /// to real coordinates via GeocodingService on tap, same as every other
  /// city-tap flow in this app). Category scope: one of Gem.categories, or
  /// 'all'.
  final String value;

  const CollectionScope.destination(this.value) : isDestination = true;
  const CollectionScope.category(this.value) : isDestination = false;
}

class CuratedCollection {
  final String title;
  final String subtitle;
  final String coverImageUrl;
  final CollectionScope scope;

  const CuratedCollection({
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.scope,
  });
}

class CuratedCollections {
  static const List<CuratedCollection> all = [
    CuratedCollection(
      title: 'Explore Hanoi',
      subtitle: "Vietnam's capital — Old Quarter, lakes & street food",
      coverImageUrl:
          'https://images.unsplash.com/photo-1509030450996-dd1a26dda07a?w=800&q=80',
      scope: CollectionScope.destination('Hanoi'),
    ),
    CuratedCollection(
      title: 'Explore Ho Chi Minh City',
      subtitle: 'Markets, rooftop cafés & war history',
      coverImageUrl:
          'https://images.unsplash.com/photo-1583417319070-4a69db38a482?w=800&q=80',
      scope: CollectionScope.destination('Ho Chi Minh City'),
    ),
    CuratedCollection(
      title: 'Trending: Hiking Trails',
      subtitle: 'Real trails, tagged by real hikers',
      coverImageUrl:
          'https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&q=80',
      scope: CollectionScope.category('hiking'),
    ),
    CuratedCollection(
      title: 'Hidden Food & Cafés',
      subtitle: 'Spots you won\'t find on a map app',
      coverImageUrl:
          'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800&q=80',
      scope: CollectionScope.category('food'),
    ),
  ];
}

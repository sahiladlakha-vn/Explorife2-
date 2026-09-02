import 'gem.dart';

/// One step in a [Tour]'s itinerary — a short title (e.g. "Old Quarter walk")
/// with an optional longer description. Deliberately just two free-text
/// fields, not a richer structured stop (no lat/lng, no duration-per-step) —
/// nothing in this app needs to plot or time an itinerary step yet, and
/// adding fields with no real use is exactly what this content type exists
/// to avoid doing to Gem.
class TourItineraryStep {
  final String title;
  final String? description;

  const TourItineraryStep({required this.title, this.description});

  factory TourItineraryStep.fromJson(Map<String, dynamic> json) =>
      TourItineraryStep(
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
      };
}

/// A bookable, priced experience (day tour, multi-stop trip) — deliberately
/// its own entity, separate from [Gem]. Gem Detail's design omits fields
/// with no real data source rather than fabricating them (no rating field
/// exists there, by design); Tour exists precisely so that principle
/// doesn't get bent for Gems when price/availability/booking needs a real
/// home.
///
/// No `rating`/`ratingBreakdown`/`reviews` fields — confirmed with product
/// (2026-09-01): this app has no real booking/payment backend and no
/// external booking-partner integration, so there is no legitimate source
/// for "verified booking" reviews. Omitted entirely for v1 rather than
/// shipped with fabricated scores; see TourDetailScreen's doc comment for
/// what happens instead.
///
/// [category] reuses [Gem.categories] (confirmed with product — day tours
/// and multi-stop trips still describe a type of experience that fits the
/// existing taxonomy, e.g. a cave tour, a coastal boat trip) rather than a
/// second parallel category system.
///
/// Backs `public.tours` — publicly readable, no client-side create/update
/// (no creation UI exists yet; content is added directly in Supabase, same
/// as this app's other curated-but-not-yet-authorable content).
class Tour {
  final String id;
  final String name;
  final List<String> photos;

  /// One of [Gem.categories], or null if uncategorized.
  final String? category;

  final int priceFrom;
  final String currency;

  /// Free text, e.g. "Full day", "4–8 hours" — confirmed with product: no
  /// structured duration type, matching cancellationPolicy's own reasoning.
  final String? durationLabel;

  /// Free text (confirmed with product over a structured cutoff/refund-%
  /// model — there's no booking flow yet to actually enforce a structured
  /// policy against, so structuring it now would be speculative).
  final String? cancellationPolicy;

  final bool pickupIncluded;
  final String? pickupDetail;

  final List<String> guideLanguages;
  final List<String> includes;
  final List<TourItineraryStep> itinerary;
  final List<String> highlights;
  final String? fullDescription;

  /// Drives the "Top pick" badge — set explicitly by whoever curates this
  /// content, never derived from a rating/popularity score (there isn't
  /// one to derive it from, and even if there were, "top pick" should stay
  /// an editorial call, not an algorithm's).
  final bool isCurated;

  final DateTime createdAt;

  const Tour({
    required this.id,
    required this.name,
    this.photos = const [],
    this.category,
    required this.priceFrom,
    this.currency = 'VND',
    this.durationLabel,
    this.cancellationPolicy,
    this.pickupIncluded = false,
    this.pickupDetail,
    this.guideLanguages = const [],
    this.includes = const [],
    this.itinerary = const [],
    this.highlights = const [],
    this.fullDescription,
    this.isCurated = false,
    required this.createdAt,
  });

  factory Tour.fromJson(Map<String, dynamic> json) => Tour(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unnamed tour',
        photos: (json['photos'] as List?)?.cast<String>() ?? const [],
        category: json['category'] as String?,
        priceFrom: (json['price_from'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'VND',
        durationLabel: json['duration_label'] as String?,
        cancellationPolicy: json['cancellation_policy'] as String?,
        pickupIncluded: json['pickup_included'] as bool? ?? false,
        pickupDetail: json['pickup_detail'] as String?,
        guideLanguages:
            (json['guide_languages'] as List?)?.cast<String>() ?? const [],
        includes: (json['includes'] as List?)?.cast<String>() ?? const [],
        itinerary: (json['itinerary'] as List?)
                ?.map((e) => TourItineraryStep.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        highlights: (json['highlights'] as List?)?.cast<String>() ?? const [],
        fullDescription: json['full_description'] as String?,
        isCurated: json['is_curated'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  String? get coverPhoto => photos.isNotEmpty ? photos.first : null;

  String get displayCategory => category != null && category!.isNotEmpty
      ? category![0].toUpperCase() + category!.substring(1)
      : 'Experience';

  /// Reuses Gem's own category → emoji map (same taxonomy) rather than a
  /// second copy: falls back to a generic compass for an uncategorized tour.
  String get emoji => Gem.categoryEmoji[category] ?? '🧭';
}

import '../core/services/mapbox_search_service.dart';

/// A real place from Mapbox Search Box — a searchable "destination" distinct
/// from [Gem] (this app's own crowdsourced hidden spots; see
/// lib/models/gem.dart). Mapbox has no pricing/reviews/amenities data, so
/// this only carries what's actually real: identity, location, and Mapbox's
/// own POI category. [latitude]/[longitude] are 0 until resolved — see
/// [hasCoords] — because Search Box's `/suggest` step (which builds the
/// picklist) deliberately omits coordinates; only retrieving one specific
/// suggestion via [DestinationProvider.resolve] fetches them.
class Destination {
  final String id; // Mapbox's mapbox_id
  final String name;
  final String placeFormatted;
  final double latitude;
  final double longitude;
  final String? category;
  bool isSaved;

  Destination({
    required this.id,
    required this.name,
    required this.placeFormatted,
    this.latitude = 0,
    this.longitude = 0,
    this.category,
    this.isSaved = false,
  });

  factory Destination.fromSuggestion(PlaceSuggestion s, {bool isSaved = false}) => Destination(
        id: s.mapboxId,
        name: s.name,
        placeFormatted: s.placeFormatted,
        category: s.category,
        isSaved: isSaved,
      );

  factory Destination.fromPlaceDetails(PlaceDetails d, {bool isSaved = false}) => Destination(
        id: d.mapboxId,
        name: d.name,
        placeFormatted: d.placeFormatted,
        latitude: d.lat,
        longitude: d.lng,
        category: d.category,
        isSaved: isSaved,
      );

  bool get hasCoords => latitude != 0 || longitude != 0;
}

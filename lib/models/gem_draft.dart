import 'gem.dart';

/// The outcome of validating a [GemDraft] — pure data, no UI involvement.
class GemDraftValidation {
  final bool isValid;

  /// Human-readable reason the name field is invalid, or null when fine.
  final String? nameError;

  const GemDraftValidation({required this.isValid, this.nameError});
}

/// An in-progress gem being authored in the Drop a Gem form.
///
/// Plain, immutable value type with **no Flutter or Supabase dependency**, so
/// the placement / validation / coordinate-formatting logic can be unit-tested
/// without a widget tree or a network. The view owns the text controllers; on
/// each change it builds a [GemDraft] and asks whether it [canPublish]. The
/// repository turns an approved draft into a row via [toGem] → [Gem.toInsert].
class GemDraft {
  final String name;
  final String category;
  final String? tagline;
  final String? description;
  final double lat;
  final double lng;
  final String? address;
  final bool hasPhoto;

  const GemDraft({
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.tagline,
    this.description,
    this.address,
    this.hasPhoto = false,
  });

  static const int maxTaglineLength = 80;
  static const int maxDescriptionLength = 600;

  /// Minimum bar to publish: a non-empty name plus valid coordinates. Tagline,
  /// description and photo are all optional and never block submission.
  bool get canPublish => validate().isValid;

  GemDraftValidation validate() {
    if (name.trim().isEmpty) {
      return const GemDraftValidation(
          isValid: false, nameError: 'Name is required');
    }
    if (!isValidLat(lat) || !isValidLng(lng)) {
      return const GemDraftValidation(isValid: false);
    }
    return const GemDraftValidation(isValid: true);
  }

  static bool isValidLat(double v) => v >= -90 && v <= 90;
  static bool isValidLng(double v) => v >= -180 && v <= 180;

  /// Empty/whitespace normalizes to null so we never persist blank strings.
  String? get normalizedTagline => _nullIfBlank(tagline);
  String? get normalizedDescription => _nullIfBlank(description);

  static String? _nullIfBlank(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Builds the typed [Gem]. `id` is empty and `savedAt` is a placeholder — the
  /// database assigns the real values on insert; the repository serializes via
  /// [Gem.toInsert], which ignores both.
  Gem toGem() => Gem(
        id: '',
        gemName: name.trim(),
        category: category,
        latitude: lat,
        longitude: lng,
        tagline: normalizedTagline,
        description: normalizedDescription,
        gemLocation: address,
        savedAt: DateTime.now(),
      );

  /// Formats a coordinate pair like "10.77621° N   ·   106.69551° E".
  static String formatCoordinates(double lat, double lng, {int precision = 5}) {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(precision)}° $ns   ·   '
        '${lng.abs().toStringAsFixed(precision)}° $ew';
  }
}

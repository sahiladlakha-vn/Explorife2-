// Pure unit tests for GemDraft — the form's validation, normalization and
// coordinate-formatting logic, with no widget tree, Supabase or network.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/gem_draft.dart';

GemDraft _draft({
  String name = 'Hidden Rooftop',
  String category = 'viewpoint',
  double lat = 10.78,
  double lng = 106.7,
  String? tagline,
  String? description,
  String? address,
  bool hasPhoto = false,
}) =>
    GemDraft(
      name: name,
      category: category,
      lat: lat,
      lng: lng,
      tagline: tagline,
      description: description,
      address: address,
      hasPhoto: hasPhoto,
    );

void main() {
  group('GemDraft.validate', () {
    test('valid when name present and coordinates in range', () {
      final v = _draft().validate();
      expect(v.isValid, isTrue);
      expect(v.nameError, isNull);
    });

    test('invalid with a clear error when name is blank', () {
      final v = _draft(name: '   ').validate();
      expect(v.isValid, isFalse);
      expect(v.nameError, isNotNull);
    });

    test('canPublish mirrors validate().isValid', () {
      expect(_draft().canPublish, isTrue);
      expect(_draft(name: '').canPublish, isFalse);
    });

    test('invalid when coordinates are out of range', () {
      expect(_draft(lat: 91).canPublish, isFalse);
      expect(_draft(lng: -181).canPublish, isFalse);
    });

    test('tagline, description and photo are optional, never blocking', () {
      expect(_draft(tagline: null, description: null, hasPhoto: false).canPublish,
          isTrue);
    });
  });

  group('GemDraft normalization', () {
    test('blank tagline/description normalize to null', () {
      final d = _draft(tagline: '   ', description: '');
      expect(d.normalizedTagline, isNull);
      expect(d.normalizedDescription, isNull);
    });

    test('non-blank values are trimmed', () {
      final d = _draft(tagline: '  crisp  ', description: '  details ');
      expect(d.normalizedTagline, 'crisp');
      expect(d.normalizedDescription, 'details');
    });
  });

  group('GemDraft.toGem', () {
    test('maps trimmed fields and keeps tagline first-class', () {
      final gem = _draft(
        name: '  Cave Pool  ',
        tagline: '  the best swim  ',
        description: '  bring shoes ',
        address: 'Ninh Binh',
      ).toGem();

      expect(gem.gemName, 'Cave Pool');
      expect(gem.tagline, 'the best swim');
      expect(gem.description, 'bring shoes');
      expect(gem.gemLocation, 'Ninh Binh');
      expect(gem.latitude, 10.78);
      expect(gem.longitude, 106.7);
    });
  });

  group('GemDraft.formatCoordinates', () {
    test('formats hemispheres and precision', () {
      expect(
        GemDraft.formatCoordinates(10.776215, 106.700981),
        '10.77622° N   ·   106.70098° E',
      );
      expect(
        GemDraft.formatCoordinates(-33.8688, -151.2093),
        '33.86880° S   ·   151.20930° W',
      );
    });
  });
}

// Locks Bug 1 (sheet count disagreeing with the map markers) from regressing:
// the header total, the chip counts and the map markers must all be drawn from
// the SAME mappable set. This asserts the one invariant that guarantees it —
// `mappableCount(selectedCategory) == mappableGems.length` — over every filter,
// with the same coords predicate the markers use.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:explorife/models/gem.dart';
import 'package:explorife/models/gem_draft.dart';
import 'package:explorife/providers/gem_provider.dart';
import 'package:explorife/repositories/gem_repository.dart';

/// Fake whose [fetchGems] returns a fixed mix of gems: some with coordinates
/// (map-eligible) and some without, across two categories.
class _SeededRepo implements GemRepository {
  final _inserts = StreamController<Gem>.broadcast();
  final _deletes = StreamController<String>.broadcast();

  static final List<Gem> seed = [
    _g('a', 'hiking', lat: 1, lng: 1), // mappable
    _g('b', 'hiking', lat: 2, lng: 2), // mappable
    _g('c', 'food', lat: 3, lng: 3), //   mappable
    _g('d', 'hiking'), //                 no coords → not mappable
    _g('e', 'food'), //                   no coords → not mappable
  ];

  static Gem _g(String id, String cat, {double? lat, double? lng}) => Gem(
        id: id,
        gemName: 'Gem $id',
        category: cat,
        latitude: lat,
        longitude: lng,
        savedAt: DateTime(2026),
      );

  @override
  Stream<Gem> get gemInserts => _inserts.stream;
  @override
  Stream<String> get gemDeletes => _deletes.stream;

  @override
  Future<List<Gem>> fetchGems({int limit = 100}) async => List.of(seed);

  @override
  Future<Gem?> fetchById(String id) async => null;
  @override
  Future<List<Gem>> fetchRelated(String category, String excludeId) async => [];
  @override
  Future<Gem> create(GemDraft draft,
          {required String userId,
          List<String> photoUrls = const [],
          Map<String, String> photoCaptions = const {}}) =>
      throw UnimplementedError();
  @override
  Future<List<String>> uploadPhotos(String userId, List<XFile> files) async =>
      [];
  @override
  Future<List<Gem>> fetchSavedGems() async => [];
  @override
  Future<Set<String>> savedGemIds() async => const {};
  @override
  Future<void> saveGem(String gemId) async {}
  @override
  Future<void> unsaveGem(String gemId) async {}
  @override
  void connectRealtime() {}
  @override
  Future<void> dispose() async {
    await _inserts.close();
    await _deletes.close();
  }
}

void main() {
  late _SeededRepo repo;
  late GemProvider provider;

  setUp(() async {
    repo = _SeededRepo();
    provider = GemProvider(repository: repo);
    // Let the constructor's _fetchGems() future settle so _gems is populated.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => provider.dispose());

  test('mappableGems only contains gems with coordinates', () {
    expect(provider.allGems.length, 5);
    expect(provider.mappableGems.length, 3);
    expect(provider.mappableGems.every((g) => g.hasCoords), isTrue);
  });

  test('mappableCount is each category own selection-independent denominator',
      () {
    expect(provider.mappableCount('all'), 3);
    expect(provider.mappableCount('hiking'), 2);
    expect(provider.mappableCount('food'), 1);
    // A category with no mappable gems counts zero, never throws.
    expect(provider.mappableCount('cave'), 0);

    // Selecting a chip must NOT change any chip's own count.
    provider.selectCategory('hiking');
    expect(provider.mappableCount('all'), 3);
    expect(provider.mappableCount('food'), 1);
  });

  test('invariant: mappableCount(selectedCategory) == mappableGems.length', () {
    for (final cat in ['all', 'hiking', 'food', 'cave']) {
      provider.selectCategory(cat);
      expect(
        provider.mappableCount(cat),
        provider.mappableGems.length,
        reason: 'count and markers diverged for "$cat"',
      );
    }
  });
}

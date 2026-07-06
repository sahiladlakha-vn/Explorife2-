// Tests for GemProvider's optimistic, in-memory save toggle. A fake repository
// stands in for the Supabase-backed one so the provider can be exercised with
// no network: it captures saveGem/unsaveGem calls and can be told to fail, so
// we can assert both the optimistic update and the rollback-on-failure path.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:explorife/models/gem.dart';
import 'package:explorife/models/gem_draft.dart';
import 'package:explorife/providers/gem_provider.dart';
import 'package:explorife/repositories/gem_repository.dart';

class FakeGemRepository implements GemRepository {
  final _inserts = StreamController<Gem>.broadcast();
  final _deletes = StreamController<String>.broadcast();
  final Set<String> saved = <String>{};
  final List<String> saveCalls = [];
  final List<String> unsaveCalls = [];

  /// When true, [saveGem] throws so we can exercise the rollback path.
  bool failNextSave = false;

  @override
  Stream<Gem> get gemInserts => _inserts.stream;
  @override
  Stream<String> get gemDeletes => _deletes.stream;

  @override
  Future<List<Gem>> fetchGems({int limit = 100}) async => [];

  @override
  Future<Gem?> fetchById(String id) async => null;

  @override
  Future<List<Gem>> fetchRelated(String category, String excludeId) async => [];

  @override
  Future<Gem> create(GemDraft draft,
          {required String userId, String? photoUrl}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> uploadPhotos(String userId, List<XFile> files) async =>
      [];

  @override
  Set<String> get savedGemIds => Set.unmodifiable(saved);

  @override
  Future<void> saveGem(String gemId) async {
    saveCalls.add(gemId);
    if (failNextSave) {
      failNextSave = false;
      throw Exception('boom');
    }
    saved.add(gemId);
  }

  @override
  Future<void> unsaveGem(String gemId) async {
    unsaveCalls.add(gemId);
    saved.remove(gemId);
  }

  @override
  void connectRealtime() {}

  @override
  Future<void> dispose() async {
    await _inserts.close();
    await _deletes.close();
  }
}

Gem _gem(String id) => Gem(id: id, gemName: 'Gem $id', savedAt: DateTime(2026));

void main() {
  late FakeGemRepository repo;
  late GemProvider provider;

  setUp(() async {
    repo = FakeGemRepository();
    provider = GemProvider(repository: repo);
    // Let the constructor's _fetchGems() future settle.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => provider.dispose());

  test('toggleSave updates state optimistically, before the repo settles', () {
    final gem = _gem('a');
    expect(provider.isSaved(gem.id), isFalse);

    final future = provider.toggleSave(gem); // not awaited
    // The set has already flipped + listeners notified synchronously.
    expect(provider.isSaved(gem.id), isTrue);
    return future;
  });

  test('toggleSave saves then unsaves, delegating to the repo seam', () async {
    final gem = _gem('b');

    await provider.toggleSave(gem);
    expect(provider.isSaved(gem.id), isTrue);
    expect(repo.saveCalls, [gem.id]);

    await provider.toggleSave(gem);
    expect(provider.isSaved(gem.id), isFalse);
    expect(repo.unsaveCalls, [gem.id]);
  });

  test('toggleSave notifies listeners', () async {
    final gem = _gem('c');
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.toggleSave(gem);
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('rolls back the optimistic add when the repo save fails', () async {
    final gem = _gem('d');
    repo.failNextSave = true;

    final future = provider.toggleSave(gem);
    expect(provider.isSaved(gem.id), isTrue); // optimistic
    await future;
    expect(provider.isSaved(gem.id), isFalse); // rolled back after failure
  });
}

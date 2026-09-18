import 'package:flutter/foundation.dart';
import '../models/curated_collection.dart';
import '../repositories/curated_collection_repository.dart';

/// Lifecycle of the collections list load — mirrors TourStatus.
enum CuratedCollectionStatus { initial, loading, ready, error }

/// Single source of truth for Home's "EXPLORE IDEAS" rail — mirrors
/// TourProvider's shape exactly. Read-only (no publish/create method):
/// there's no creation UI for this content yet. Registered as a plain
/// ChangeNotifierProvider, no auth dependency — curated collections are
/// public, readable content, same as Tours/Gems' public read path.
class CuratedCollectionProvider extends ChangeNotifier {
  CuratedCollectionProvider({CuratedCollectionRepository? repository})
      : _repo = repository ?? CuratedCollectionRepository() {
    _fetch();
  }

  final CuratedCollectionRepository _repo;

  List<CuratedCollection> _collections = [];
  CuratedCollectionStatus _status = CuratedCollectionStatus.initial;
  String? _error;

  List<CuratedCollection> get collections => List.unmodifiable(_collections);
  bool get loading => _status == CuratedCollectionStatus.loading;
  bool get hasError => _status == CuratedCollectionStatus.error;
  String? get error => _error;

  Future<void> _fetch() async {
    _status = CuratedCollectionStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _collections = await _repo.fetchAll();
      _status = CuratedCollectionStatus.ready;
    } catch (_) {
      _error = 'Check your connection and try again.';
      _status = CuratedCollectionStatus.error;
    }
    notifyListeners();
  }

  Future<void> refresh() => _fetch();
}

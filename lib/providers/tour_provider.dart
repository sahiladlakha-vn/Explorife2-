import 'package:flutter/foundation.dart';
import '../models/tour.dart';
import '../repositories/tour_repository.dart';

/// Lifecycle of the tour list load — mirrors GemStatus.
enum TourStatus { initial, loading, ready, error }

/// Single source of truth for tour state — mirrors GemProvider's shape.
/// Read-only (no publish/create method): there's no creation UI for Tour
/// yet. Registered as a plain ChangeNotifierProvider, no auth dependency —
/// tours are public, readable content, same as Gems' public read path.
class TourProvider extends ChangeNotifier {
  TourProvider({TourRepository? repository})
      : _repo = repository ?? TourRepository() {
    _fetchTours();
  }

  final TourRepository _repo;

  List<Tour> _tours = [];
  TourStatus _status = TourStatus.initial;
  String? _error;

  List<Tour> get tours => List.unmodifiable(_tours);
  bool get loading => _status == TourStatus.loading;
  bool get hasError => _status == TourStatus.error;
  String? get error => _error;

  Tour? byId(String id) {
    for (final t in _tours) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _fetchTours() async {
    _status = TourStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _tours = await _repo.fetchTours();
      _status = TourStatus.ready;
    } catch (_) {
      _error = 'Check your connection and try again.';
      _status = TourStatus.error;
    }
    notifyListeners();
  }

  Future<void> refresh() => _fetchTours();

  /// Fetches a single tour by id — used when opening TourDetailScreen for a
  /// tour not already cached in [tours] (e.g. a deep link).
  Future<Tour?> fetchById(String id) => _repo.fetchById(id);
}

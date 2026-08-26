// Tests for BookingProvider's optimistic mutations and rollback-on-failure
// paths. A fake repository stands in for the Supabase-backed one (mirrors
// FakeGemRepository in gem_provider_save_test.dart) so the provider can be
// exercised with no network — and so the sentinel-based `update()` clearing
// logic (the actual bug fixed this session) has real regression coverage
// down to the wire-level patch it sends.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/models/trip_booking.dart';
import 'package:explorife/providers/booking_provider.dart';
import 'package:explorife/repositories/booking_repository.dart';

class FakeBookingRepository implements BookingRepository {
  final Map<String, List<TripBooking>> byTrip = {};
  final List<Map<String, dynamic>> patchCalls = [];
  final List<String> deleteCalls = [];
  int _seq = 0;

  /// When set, the next call to the named method throws this instead of
  /// succeeding — used to exercise each rollback path.
  Object? failNextFetch;
  Object? failNextInsert;
  Object? failNextPatch;
  Object? failNextDelete;

  @override
  Future<List<TripBooking>> fetchForTrip(String tripId) async {
    if (failNextFetch != null) {
      final e = failNextFetch!;
      failNextFetch = null;
      throw e;
    }
    return List.of(byTrip[tripId] ?? const []);
  }

  @override
  Future<TripBooking> insert({
    required String tripId,
    String? stopId,
    required BookingType bookingType,
    required String title,
    String? confirmationRef,
    String? provider,
    DateTime? startAt,
    DateTime? endAt,
    int? amountVnd,
    required BookingStatus status,
    required String? createdBy,
  }) async {
    if (failNextInsert != null) {
      final e = failNextInsert!;
      failNextInsert = null;
      throw e;
    }
    final saved = TripBooking(
      id: 'server_${_seq++}',
      tripId: tripId,
      stopId: stopId,
      bookingType: bookingType,
      title: title,
      confirmationRef: confirmationRef,
      provider: provider,
      startAt: startAt,
      endAt: endAt,
      amountVnd: amountVnd,
      status: status,
      createdBy: createdBy,
      createdAt: DateTime(2026, 1, 1),
    );
    byTrip.putIfAbsent(tripId, () => []).add(saved);
    return saved;
  }

  @override
  Future<void> patch(String bookingId, Map<String, dynamic> fields) async {
    patchCalls.add({'id': bookingId, ...fields});
    if (failNextPatch != null) {
      final e = failNextPatch!;
      failNextPatch = null;
      throw e;
    }
  }

  @override
  Future<void> delete(String bookingId) async {
    deleteCalls.add(bookingId);
    if (failNextDelete != null) {
      final e = failNextDelete!;
      failNextDelete = null;
      throw e;
    }
  }
}

void main() {
  late FakeBookingRepository repo;
  late BookingProvider provider;

  setUp(() {
    repo = FakeBookingRepository();
    provider = BookingProvider(repository: repo);
  });

  group('fetchForTrip', () {
    test('populates bookingsFor and flips hasLoaded', () async {
      repo.byTrip['trip1'] = [
        TripBooking(
          id: 'b1',
          tripId: 'trip1',
          bookingType: BookingType.flight,
          title: 'VN203',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      expect(provider.hasLoaded('trip1'), isFalse);
      await provider.fetchForTrip('trip1');
      expect(provider.hasLoaded('trip1'), isTrue);
      expect(provider.bookingsFor('trip1'), hasLength(1));
      expect(provider.bookingsFor('trip1').first.title, 'VN203');
      expect(provider.errorFor('trip1'), isNull);
    });

    test('is idempotent — a second call is a no-op unless forced', () async {
      repo.byTrip['trip1'] = [
        TripBooking(
          id: 'b1',
          tripId: 'trip1',
          bookingType: BookingType.activity,
          title: 'First',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      await provider.fetchForTrip('trip1');

      // Change the backing data without forcing a refetch.
      repo.byTrip['trip1']!.add(TripBooking(
        id: 'b2',
        tripId: 'trip1',
        bookingType: BookingType.activity,
        title: 'Second',
        createdAt: DateTime(2026, 1, 1),
      ));
      await provider.fetchForTrip('trip1');
      expect(provider.bookingsFor('trip1'), hasLength(1)); // still stale

      await provider.fetchForTrip('trip1', force: true);
      expect(provider.bookingsFor('trip1'), hasLength(2)); // now refreshed
    });

    test('an unloaded, never-fetched trip has no error and an empty list',
        () {
      expect(provider.hasLoaded('unknown'), isFalse);
      expect(provider.bookingsFor('unknown'), isEmpty);
      expect(provider.errorFor('unknown'), isNull);
    });

    test('a failed fetch leaves hasLoaded false and records the error', () async {
      repo.failNextFetch = Exception('network down');
      await provider.fetchForTrip('trip1');
      expect(provider.hasLoaded('trip1'), isFalse);
      expect(provider.errorFor('trip1'), contains('network down'));
      expect(provider.bookingsFor('trip1'), isEmpty);
    });
  });

  group('add', () {
    test('appears immediately (optimistic) before the repo call settles', () {
      final future = provider.add(
        tripId: 'trip1',
        bookingType: BookingType.stay,
        title: 'Hotel',
        createdBy: 'user1',
      );
      expect(provider.bookingsFor('trip1'), hasLength(1));
      expect(provider.bookingsFor('trip1').first.id, startsWith('temp_'));
      return future;
    });

    test('reconciles the temp row to the server-assigned id on success',
        () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.stay,
        title: 'Hotel',
        createdBy: 'user1',
      );
      expect(saved.id, startsWith('server_'));
      expect(provider.bookingsFor('trip1'), hasLength(1));
      expect(provider.bookingsFor('trip1').first.id, saved.id);
    });

    test('rolls back the optimistic row when the insert fails', () async {
      repo.failNextInsert = Exception('insert failed');
      await expectLater(
        provider.add(
          tripId: 'trip1',
          bookingType: BookingType.stay,
          title: 'Hotel',
          createdBy: 'user1',
        ),
        throwsException,
      );
      expect(provider.bookingsFor('trip1'), isEmpty);
      expect(provider.errorFor('trip1'), contains('insert failed'));
    });

    test('preserves the MONEY CONTRACT — a null amountVnd is TBD, never '
        'coalesced to 0', () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.activity,
        title: 'Free walking tour',
        amountVnd: null,
        createdBy: 'user1',
      );
      expect(saved.amountVnd, isNull);
      expect(saved.hasKnownAmount, isFalse);
    });
  });

  group('updateStatus', () {
    test('flips optimistically and sends the wire value to the repo', () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.flight,
        title: 'VN203',
        createdBy: 'user1',
      );
      await provider.updateStatus(saved.id, BookingStatus.paid);
      expect(provider.bookingsFor('trip1').first.status, BookingStatus.paid);
      expect(repo.patchCalls.last, {'id': saved.id, 'status': 'paid'});
    });

    test('rolls back to the old status when the patch fails', () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.flight,
        title: 'VN203',
        status: BookingStatus.toBook,
        createdBy: 'user1',
      );
      repo.failNextPatch = Exception('patch failed');
      await expectLater(
        provider.updateStatus(saved.id, BookingStatus.paid),
        throwsException,
      );
      expect(provider.bookingsFor('trip1').first.status, BookingStatus.toBook);
    });

    test('a temp (not-yet-persisted) booking never reaches the repo', () async {
      // Fire-and-forget the add so the booking is still in its temp-id state.
      final addFuture = provider.add(
        tripId: 'trip1',
        bookingType: BookingType.flight,
        title: 'VN203',
        createdBy: 'user1',
      );
      final tempId = provider.bookingsFor('trip1').first.id;
      await provider.updateStatus(tempId, BookingStatus.paid);
      expect(repo.patchCalls, isEmpty);
      await addFuture; // let the pending insert settle before the test ends
    });
  });

  group('updateAmount', () {
    test('sets a real amount', () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.stay,
        title: 'Hotel',
        createdBy: 'user1',
      );
      await provider.updateAmount(saved.id, 500000);
      expect(provider.bookingsFor('trip1').first.amountVnd, 500000);
      expect(repo.patchCalls.last, {'id': saved.id, 'amount_vnd': 500000});
    });

    test('clears back to TBD (null), the MONEY CONTRACT\'s explicit-null path',
        () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.stay,
        title: 'Hotel',
        amountVnd: 500000,
        createdBy: 'user1',
      );
      await provider.updateAmount(saved.id, null);
      expect(provider.bookingsFor('trip1').first.amountVnd, isNull);
      expect(repo.patchCalls.last, {'id': saved.id, 'amount_vnd': null});
    });
  });

  group('update — sentinel-based general edit (the actual bug fix)', () {
    late TripBooking saved;

    setUp(() async {
      saved = await provider.add(
        tripId: 'trip1',
        stopId: 'stop1',
        bookingType: BookingType.stay,
        title: 'Hanoi Hilton',
        confirmationRef: 'CONF1',
        provider: 'Hilton',
        startAt: DateTime.utc(2026, 8, 14),
        endAt: DateTime.utc(2026, 8, 16),
        amountVnd: 1500000,
        createdBy: 'user1',
      );
      repo.patchCalls.clear();
    });

    test('omitting every arg sends no patch at all (nothing changed)',
        () async {
      await provider.update(saved.id);
      expect(repo.patchCalls, isEmpty);
      final current = provider.bookingsFor('trip1').first;
      expect(current.confirmationRef, 'CONF1');
      expect(current.stopId, 'stop1');
    });

    test('passing explicit null CLEARS stopId, in-memory and on the wire',
        () async {
      await provider.update(saved.id, stopId: null);
      expect(provider.bookingsFor('trip1').first.stopId, isNull);
      expect(repo.patchCalls.single, {'id': saved.id, 'stop_id': null});
    });

    test('passing explicit null CLEARS confirmationRef on the wire', () async {
      await provider.update(saved.id, confirmationRef: null);
      expect(provider.bookingsFor('trip1').first.confirmationRef, isNull);
      expect(
          repo.patchCalls.single, {'id': saved.id, 'confirmation_ref': null});
    });

    test('setting one field and clearing another in the same call sends '
        'exactly those two wire columns', () async {
      await provider.update(saved.id, provider: 'Marriott', stopId: null);
      final current = provider.bookingsFor('trip1').first;
      expect(current.provider, 'Marriott');
      expect(current.stopId, isNull);
      expect(current.confirmationRef, 'CONF1'); // untouched
      expect(repo.patchCalls.single,
          {'id': saved.id, 'provider': 'Marriott', 'stop_id': null});
    });

    test('rolls back the whole booking to its pre-edit state when the patch '
        'fails', () async {
      repo.failNextPatch = Exception('patch failed');
      await expectLater(
        provider.update(saved.id, title: 'Renamed', stopId: null),
        throwsException,
      );
      final current = provider.bookingsFor('trip1').first;
      expect(current.title, 'Hanoi Hilton');
      expect(current.stopId, 'stop1');
    });
  });

  group('remove', () {
    test('removes immediately (optimistic)', () async {
      final saved = await provider.add(
        tripId: 'trip1',
        bookingType: BookingType.activity,
        title: 'Tour',
        createdBy: 'user1',
      );
      final future = provider.remove(saved.id);
      expect(provider.bookingsFor('trip1'), isEmpty);
      await future;
      expect(repo.deleteCalls, [saved.id]);
    });

    test('restores the booking at its original position when the delete '
        'fails', () async {
      final a = await provider.add(
          tripId: 'trip1',
          bookingType: BookingType.activity,
          title: 'A',
          createdBy: 'user1');
      final b = await provider.add(
          tripId: 'trip1',
          bookingType: BookingType.activity,
          title: 'B',
          startAt: DateTime.utc(2026, 8, 14),
          createdBy: 'user1');

      repo.failNextDelete = Exception('delete failed');
      await expectLater(provider.remove(a.id), throwsException);

      final ids = provider.bookingsFor('trip1').map((x) => x.id).toList();
      expect(ids, containsAll([a.id, b.id]));
    });

    test('a temp (not-yet-persisted) booking never reaches the repo', () async {
      final addFuture = provider.add(
        tripId: 'trip1',
        bookingType: BookingType.activity,
        title: 'Tour',
        createdBy: 'user1',
      );
      final tempId = provider.bookingsFor('trip1').first.id;
      await provider.remove(tempId);
      expect(repo.deleteCalls, isEmpty);
      await addFuture;
    });
  });

  group('clear', () {
    test('drops every cached trip\'s bookings and loading/error state',
        () async {
      repo.byTrip['trip1'] = [
        TripBooking(
          id: 'b1',
          tripId: 'trip1',
          bookingType: BookingType.activity,
          title: 'X',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      await provider.fetchForTrip('trip1');
      expect(provider.hasLoaded('trip1'), isTrue);

      provider.clear();
      expect(provider.hasLoaded('trip1'), isFalse);
      expect(provider.bookingsFor('trip1'), isEmpty);
      expect(provider.errorFor('trip1'), isNull);
    });
  });
}

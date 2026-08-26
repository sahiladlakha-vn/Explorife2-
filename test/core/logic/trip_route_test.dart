// Regression tests for plotStops' custom-stop coordinate handling — the fix
// for a trip whose stops were all customPayload entries showing a fully
// empty map. A custom stop only plots when its own payload carries lat/lng
// (set when it was picked from a real Mapbox place; see AddStopSheet), never
// for a pure freeform name — this guards both directions so a future edit
// can't silently regress either one.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/logic/trip_route.dart';
import 'package:explorife/models/gem.dart';
import 'package:explorife/models/trip_stop.dart';

TripStop _customStop({String id = 'stop-1', Map<String, dynamic>? payload}) => TripStop(
      id: id,
      tripId: 'trip-1',
      day: 1,
      slot: 'morning',
      customPayload: payload,
    );

TripStop _gemStop(String gemId) => TripStop(
      id: 'stop-2',
      tripId: 'trip-1',
      day: 1,
      slot: 'morning',
      gemId: gemId,
    );

Gem _gem(String id, {double? lat, double? lng}) => Gem(
      id: id,
      gemName: 'Test Gem',
      latitude: lat,
      longitude: lng,
      savedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('a custom stop with no payload does not plot', () {
    expect(plotStops([_customStop()], const []), isEmpty);
  });

  test('a custom stop with a title but no lat/lng does not plot', () {
    final stops = [_customStop(payload: {'title': 'Airport taxi'})];
    expect(plotStops(stops, const []), isEmpty);
  });

  test('a custom stop with lat/lng in its payload plots at those coordinates', () {
    final stops = [
      _customStop(payload: {'title': 'Independence Palace', 'lat': 10.7772, 'lng': 106.6953}),
    ];
    final plotted = plotStops(stops, const []);
    expect(plotted, hasLength(1));
    expect(plotted.first.lat, 10.7772);
    expect(plotted.first.lng, 106.6953);
    expect(plotted.first.gem.gemName, 'Independence Palace');
  });

  test('a gem stop still plots via the gem\'s own coordinates', () {
    final gem = _gem('gem-1', lat: 10.82, lng: 106.71);
    final plotted = plotStops([_gemStop('gem-1')], [gem]);
    expect(plotted, hasLength(1));
    expect(plotted.first.lat, 10.82);
    expect(plotted.first.lng, 106.71);
  });

  test('a gem stop referencing a gem with no coordinates does not plot', () {
    final gem = _gem('gem-1');
    expect(plotStops([_gemStop('gem-1')], [gem]), isEmpty);
  });

  test('a mix of a coordinate-less custom stop and a plottable one only plots the latter', () {
    final stops = [
      _customStop(id: 'stop-1', payload: {'title': 'Airport taxi'}),
      _customStop(
          id: 'stop-2',
          payload: {'title': 'Highlands Central Post Office', 'lat': 10.78, 'lng': 106.7}),
    ];
    final plotted = plotStops(stops, const []);
    expect(plotted, hasLength(1));
    expect(plotted.first.gem.gemName, 'Highlands Central Post Office');
  });
}

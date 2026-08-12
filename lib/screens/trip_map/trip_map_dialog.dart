import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../../core/logic/trip_route.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/gem_provider.dart';
import '../../providers/trip_provider.dart';
import '../explore/map_engine.dart';

/// Centered modal card showing a trip's full interactive route map — opened
/// via `showDialog` from the Overview tab's trip card (tapping its static
/// map thumbnail), dimmed backdrop + tap-outside-to-dismiss, same shape as
/// any other modal in the app (e.g. the trip-setup wizard's sheet). Not a
/// routed screen — there's nothing else that links here, so this doesn't
/// need a GoRoute; `Navigator.pop` closes it like any dialog.
///
/// Reuses the exact same stop-resolution logic as the Overview card's static
/// thumbnail overlay ([plotStops], lib/core/logic/trip_route.dart), just
/// uncapped: every plottable stop gets its own numbered pin here regardless
/// of trip length — the card is the one that collapses to one-pin-per-day
/// for long trips, not this.
class TripMapDialog extends StatelessWidget {
  const TripMapDialog({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final trip = context.select<TripProvider, Trip?>((p) => p.tripById(tripId));
    final isLoading = context.select<TripProvider, bool>((p) => p.isLoading);
    final error = context.select<TripProvider, String?>((p) => p.error);

    String? title, subtitle;
    Widget body;
    if (trip != null) {
      title = trip.displayName;
      subtitle =
          '${Trip.formatDateRange(trip.startDate, trip.endDate)} · ${trip.nights} ${trip.nights == 1 ? 'night' : 'nights'}';
      body = _TripMapView(trip: trip);
    } else if (isLoading) {
      body = const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    } else if (error != null) {
      body = const Center(
        child: Text("Couldn't load this trip.",
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    } else {
      body = const Center(
        child: Text("This trip doesn't exist or isn't yours.",
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final size = MediaQuery.of(context).size;
    final width = math.min(560.0, size.width * 0.92);
    final height = size.height * 0.72;

    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _Header(title: title, subtitle: subtitle),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Trip name/dates + close (X) button — same boxed-icon treatment as the
/// trip-setup wizard's close button (trip_setup_sheet.dart), scaled down to
/// fit this smaller modal card instead of a full-width app bar.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.divider),
              ),
              child: const Icon(Icons.close,
                  color: AppTheme.textPrimary, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripMapView extends StatefulWidget {
  const _TripMapView({required this.trip});
  final Trip trip;

  @override
  State<_TripMapView> createState() => _TripMapViewState();
}

class _TripMapViewState extends State<_TripMapView> {
  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';

  MapEngineController? _controller;
  String? _fittedKey;

  // Which stop's callout is currently open, if any — kept in sync with what
  // the engine actually shows via onCalloutClosed (see _onCalloutClosed),
  // not just set-and-forget, since e.g. Mapbox's Popup can close itself
  // (tapping empty map space) without Dart initiating it.
  String? _selectedStopId;

  // setState (not a bare field assignment) is the fix here: without it,
  // nothing schedules a rebuild after the engine becomes ready, so build()
  // never re-runs to let _maybeFit see a non-null _controller — the camera
  // silently stays at the engine's hardcoded default (Vietnam-area, zoom
  // ~2.6-3) instead of ever calling fitMarkers.
  void _onReady(MapEngineController controller) =>
      setState(() => _controller = controller);

  /// Fits the camera to every marker once per distinct stop set — guards
  /// against re-fitting on every rebuild (e.g. an unrelated provider
  /// notification), while still re-fitting if stops load in after the map
  /// is already up (the common case: TripProvider/GemProvider haven't
  /// resolved yet on first paint).
  void _maybeFit(List<MapMarkerData> markers) {
    if (_controller == null || markers.isEmpty) return;
    final key = markers.map((m) => m.id).join(',');
    if (key == _fittedKey) return;
    _fittedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller?.fitMarkers(markers);
    });
  }

  // In-map callout, not a bottom sheet — tapping the same pin again (or
  // tapping empty map space, via _onCalloutClosed) dismisses it; tapping a
  // different pin replaces it, since only one is ever shown at a time.
  void _onMarkerTap(String stopId, List<PlottedStop> plotted) {
    if (stopId == _selectedStopId) {
      _controller?.hideCallout();
      setState(() => _selectedStopId = null);
      return;
    }
    final match = plotted.where((p) => p.stop.id == stopId).toList();
    if (match.isEmpty) return; // an arrow/day-chip marker, not a real stop
    final p = match.first;
    _controller?.showCallout(
      lat: p.lat,
      lng: p.lng,
      title: '${p.label}: ${p.gem.gemName}',
      subtitle:
          '(Day ${p.stop.day}${p.stop.startTime != null ? ', ${p.stop.startTime}' : ''})',
    );
    setState(() => _selectedStopId = stopId);
  }

  void _onCalloutClosed() {
    if (_selectedStopId != null) setState(() => _selectedStopId = null);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final gems = context.watch<GemProvider>().allGems;
    final orderedStops =
        provider.allStopsOrdered(widget.trip.id, widget.trip.nights + 1);
    // Uncapped — full per-stop detail, per this feature's brief (the
    // Overview card is the one that simplifies for long trips, not this).
    final plotted = plotStops(orderedStops, gems);

    if (plotted.isEmpty) return const _EmptyMapState();

    // One numbered pin per stop, colored by that stop's day — the primary,
    // tappable markers. Fit-to-bounds uses only these (see _maybeFit):
    // arrows sit at segment midpoints and day chips at a day's centroid, both
    // already inside the pins' own bounds, so including them wouldn't
    // change the fit, only complicate the dedup key.
    final pinMarkers = [
      for (final p in plotted)
        MapMarkerData(
          id: p.stop.id,
          lat: p.lat,
          lng: p.lng,
          emoji: p.gem.emoji,
          icon: Icons.place,
          label: p.label,
          color: Color(colorForTripDay(p.stop.day)),
        ),
    ];

    // One route + one "DAY N" chip per day, each in that day's color; a day
    // with 2+ stops also gets direction arrows along its segments. Neither
    // arrows nor chips are tappable (_onMarkerTap no-ops for an id that
    // doesn't match a real stop).
    final routes = <MapRouteSegment>[];
    final decorationMarkers = <MapMarkerData>[];
    for (final entry in groupPlottedByDay(plotted).entries) {
      final day = entry.key;
      final dayStops = entry.value;
      final color = Color(colorForTripDay(day));
      final points = [for (final p in dayStops) (lat: p.lat, lng: p.lng)];

      if (points.length >= 2) {
        routes.add(MapRouteSegment(points: points, color: color));
        for (final (i, arrow) in routeArrowPoints(points).indexed) {
          decorationMarkers.add(MapMarkerData(
            id: 'arrow-$day-$i',
            lat: arrow.lat,
            lng: arrow.lng,
            emoji: '',
            icon: Icons.arrow_upward,
            kind: MapMarkerKind.arrow,
            color: color,
            rotationDegrees: arrow.bearing,
          ));
        }
      }

      decorationMarkers.add(MapMarkerData(
        id: 'daychip-$day',
        lat: dayStops.map((p) => p.lat).reduce((a, b) => a + b) / dayStops.length,
        lng: dayStops.map((p) => p.lng).reduce((a, b) => a + b) / dayStops.length,
        emoji: '',
        icon: Icons.label,
        kind: MapMarkerKind.dayChip,
        color: color,
        label: 'DAY $day',
      ));
    }

    _maybeFit(pinMarkers);

    return MapEngineView(
      markers: [...pinMarkers, ...decorationMarkers],
      routes: routes,
      styleId: 'outdoors-v12',
      token: _token,
      onMarkerTap: (id) => _onMarkerTap(id, plotted),
      onReady: _onReady,
      onCalloutClosed: _onCalloutClosed,
    );
  }
}

class _EmptyMapState extends StatelessWidget {
  const _EmptyMapState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text('No stops planned yet',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('Add stops to this trip to see them mapped here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}


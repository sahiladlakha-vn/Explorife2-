part of '../profile_screen.dart';

// Day-scoped map panel for the My Trip tab's itinerary segment — shows pins
// for the currently-selected day's activities only (item 7 of the redesign
// brief), with a toggle to also show the rest of the trip's stops dimmed for
// context (item 8). Reuses the exact same MapEngineView/plotStops pipeline as
// the full-trip TripMapDialog (lib/screens/trip_map/trip_map_dialog.dart) —
// Mapbox GL JS on web, flutter_map on native, via the same conditional-export
// shim — rather than inventing a second map stack for this smaller panel.
//
// No TripStop/Gem model changes were needed: plotStops() already resolves
// per-stop coordinates for both gem-backed and custom stops (the latter only
// when picked from a real Mapbox search result, per customPayload['lat'/'lng']).
// A stop with no resolvable coordinates simply doesn't appear here — it isn't
// a distinct "broken" state, just one this panel can't plot.

class _DayMapPanel extends StatefulWidget {
  final int day;
  final List<TripStop> allStops;
  final Map<String, Gem> gemsById;
  const _DayMapPanel({
    required this.day,
    required this.allStops,
    required this.gemsById,
  });

  @override
  State<_DayMapPanel> createState() => _DayMapPanelState();
}

class _DayMapPanelState extends State<_DayMapPanel> {
  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';

  // Same web-vs-native style split as TripMapDialog, and for the same reason
  // (Standard Style's 3D buildings/dynamic lighting only render through a
  // real Mapbox GL runtime) — see that file's _styleId doc comment.
  String get _styleId => kIsWeb ? 'standard' : 'outdoors-v12';

  MapEngineController? _controller;
  String? _fittedKey;
  String? _selectedStopId;

  /// Whether the rest of the trip's stops are also shown, dimmed. Local,
  /// per-panel state rather than lifted to the tab — switching days keeps
  /// whatever the user last chose, but there's exactly one panel instance at
  /// a time so nothing needs to persist across it.
  bool _showFullTrip = false;

  void _onReady(MapEngineController controller) =>
      setState(() => _controller = controller);

  /// Fits the camera once per distinct (day, toggle, marker-set) combination
  /// — mirrors TripMapDialog's _maybeFit guard, extended with the day + the
  /// full-trip toggle so switching either re-fits, but an unrelated rebuild
  /// (e.g. a provider notification) doesn't yank the camera back.
  void _maybeFit(List<MapMarkerData> markers) {
    if (_controller == null || markers.isEmpty) return;
    final key =
        '${widget.day}|$_showFullTrip|${markers.map((m) => m.id).join(',')}';
    if (key == _fittedKey) return;
    _fittedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller?.fitMarkers(markers);
    });
  }

  void _onMarkerTap(String rawId, List<PlottedStop> plotted) {
    // Context (dimmed, other-day) markers are prefixed 'ctx-' so their ids
    // don't collide with the active day's own stop ids on the same map.
    final stopId = rawId.startsWith('ctx-') ? rawId.substring(4) : rawId;
    if (stopId == _selectedStopId) {
      _controller?.hideCallout();
      setState(() => _selectedStopId = null);
      return;
    }
    final match = plotted.where((p) => p.stop.id == stopId).toList();
    if (match.isEmpty) return; // an arrow marker, not a real stop
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
  void didUpdateWidget(covariant _DayMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day && _selectedStopId != null) {
      _controller?.hideCallout();
      _selectedStopId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gems = widget.gemsById.values.toList();
    final plotted = plotStops(widget.allStops, gems);

    final dayPlotted = plotted.where((p) => p.stop.day == widget.day).toList();
    final otherPlotted =
        plotted.where((p) => p.stop.day != widget.day).toList();

    if (plotted.isEmpty) {
      return _MapPanelChrome(
        child: Stack(
          children: [
            const _EmptyDayMapState(),
            Positioned(
              top: 10,
              left: 10,
              child: _StopCountCard(label: _stopCountLabel(0)),
            ),
          ],
        ),
      );
    }

    final dayColor = Color(colorForTripDay(widget.day));
    final pinMarkers = [
      for (final p in dayPlotted)
        MapMarkerData(
          id: p.stop.id,
          lat: p.lat,
          lng: p.lng,
          emoji: p.gem.emoji,
          icon: Icons.place,
          label: p.label,
          color: dayColor,
        ),
    ];

    final routes = <MapRouteSegment>[];
    final decorationMarkers = <MapMarkerData>[];
    if (dayPlotted.length >= 2) {
      final points = [for (final p in dayPlotted) (lat: p.lat, lng: p.lng)];
      routes.add(MapRouteSegment(points: points, color: dayColor));
      for (final (i, arrow) in routeArrowPoints(points).indexed) {
        decorationMarkers.add(MapMarkerData(
          id: 'arrow-$i',
          lat: arrow.lat,
          lng: arrow.lng,
          emoji: '',
          icon: Icons.arrow_upward,
          kind: MapMarkerKind.arrow,
          color: dayColor,
          rotationDegrees: arrow.bearing,
        ));
      }
    }

    // Full-trip context markers: every other day's stops, flattened to one
    // dim neutral tone rather than kept in their own per-day colors — these
    // are background context for "where am I relative to the rest of the
    // trip", not a second set of pins meant to be read closely (no labels,
    // no route lines of their own).
    final dimColor = _kMute.withValues(alpha: 0.55);
    final contextMarkers = [
      if (_showFullTrip)
        for (final p in otherPlotted)
          MapMarkerData(
            id: 'ctx-${p.stop.id}',
            lat: p.lat,
            lng: p.lng,
            emoji: '',
            icon: Icons.place,
            color: dimColor,
          ),
    ];

    final fitMarkers = pinMarkers.isNotEmpty ? pinMarkers : contextMarkers;
    _maybeFit(fitMarkers);

    return _MapPanelChrome(
      child: Stack(
        children: [
          MapEngineView(
            markers: [...contextMarkers, ...pinMarkers, ...decorationMarkers],
            routes: routes,
            styleId: _styleId,
            token: _token,
            onMarkerTap: (id) => _onMarkerTap(id, plotted),
            onReady: _onReady,
            onCalloutClosed: _onCalloutClosed,
          ),
          // Honest empty state for THIS day specifically — shown as a
          // backdrop over the map rather than replacing it outright, so the
          // dimmed full-trip context (when the toggle is on) stays visible
          // underneath instead of being hidden by the same message.
          if (dayPlotted.isEmpty)
            const Positioned.fill(child: _EmptyDayMapState(asOverlay: true)),
          // Floating "Day N stops · ..." chip, top-left — replaces the old
          // plain "MAP" header label; the count now lives over the map
          // itself, matching the dark-redesign reference.
          Positioned(
            top: 10,
            left: 10,
            child: _StopCountCard(label: _stopCountLabel(dayPlotted.length)),
          ),
          if (otherPlotted.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: _FullTripToggle(
                value: _showFullTrip,
                onChanged: (v) => setState(() => _showFullTrip = v),
              ),
            ),
          Positioned(
            bottom: 10,
            right: 10,
            child: _ZoomControls(
              onZoomIn: () => _controller?.zoomBy(1),
              onZoomOut: () => _controller?.zoomBy(-1),
            ),
          ),
        ],
      ),
    );
  }

  String _stopCountLabel(int count) => 'Day ${widget.day} stops · '
      '${count == 0 ? 'No stops yet' : '$count ${count == 1 ? 'stop' : 'stops'}'}';
}

/// Card chrome shared by every state of the day map panel (populated, no
/// day-stops-but-context-shown, and fully empty) — a flat dark-navy fill
/// (item 10 of the 2026-09-13 redesign) with no header bar of its own; the
/// stop count, the full-trip toggle, and the zoom controls all float
/// directly over the map/[child] instead, per the reference.
class _MapPanelChrome extends StatelessWidget {
  final Widget child;
  const _MapPanelChrome({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kNavy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: _MapTexture()),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Faint decorative texture behind the map/empty-state content — a soft
/// off-center radial glow plus a subtle vertical stripe grid, so the navy
/// panel reads as a stylized map rather than a flat color block. Purely
/// decorative and sits behind [_MapPanelChrome]'s child, so real map tiles
/// (whenever a day has plottable stops) paint over it entirely.
class _MapTexture extends StatelessWidget {
  const _MapTexture();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.5),
              radius: 1.1,
              colors: [
                _kTeal.withValues(alpha: 0.16),
                _kTeal.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        CustomPaint(painter: _MapGridPainter()),
      ],
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const spacing = 18.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) => false;
}

/// Small translucent floating chip, top-left, showing this day's stop count
/// — replaces the old plain "MAP" header label now that the chrome has no
/// header bar of its own.
class _StopCountCard extends StatelessWidget {
  final String label;
  const _StopCountCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return _FloatingChip(
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: _kInk)),
    );
  }
}

/// "All days" label + switch — toggles whether the rest of the trip's stops
/// render dimmed alongside the active day's own pins. Floats top-right over
/// the map, matching [_StopCountCard]'s chip treatment.
class _FullTripToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FullTripToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Show full trip, dimmed',
      value: value ? 'on' : 'off',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: _FloatingChip(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('All days',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: value ? Colors.white : _kMute)),
              const SizedBox(width: 2),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// +/- zoom control stack, bottom-right over the map (item 10).
class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return _FloatingChip(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomButton(Icons.add, onZoomIn, 'Zoom in'),
          Container(width: 26, height: 1, color: _kBorder),
          _zoomButton(Icons.remove, onZoomOut, 'Zoom out'),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap, String label) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: _kInk),
        ),
      ),
    );
  }
}

/// Shared translucent dark chip background for everything that floats over
/// the map surface (stop count, full-trip toggle, zoom controls) — one
/// consistent "glass over navy" treatment rather than each inventing its own.
class _FloatingChip extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _FloatingChip({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _kCard.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    );
  }
}

/// "No stops on the map yet" — the honest empty state item 7 calls for,
/// distinct from _EmptyMapState in trip_map_dialog.dart (that one is worded
/// for "this trip has nothing plannable at all"; this one can fire per-day
/// even when the trip overall has plenty of stops elsewhere). [asOverlay]
/// renders a translucent backdrop so it can sit over a still-visible dimmed
/// full-trip map instead of blanking it out.
class _EmptyDayMapState extends StatelessWidget {
  final bool asOverlay;
  const _EmptyDayMapState({this.asOverlay = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: asOverlay ? _kNavy.withValues(alpha: 0.86) : null,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 32, color: _kMute),
            const SizedBox(height: 10),
            Text('No stops on the map yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _kInk,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('Add a place to see it here',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11.5, color: _kMute)),
          ],
        ),
      ),
    );
  }
}

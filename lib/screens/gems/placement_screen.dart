import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../providers/gem_provider.dart';
import '../explore/map_engine.dart';
import 'drop_gem_sheet.dart';

/// Step 2 of the Drop a Gem flow: a full-screen map with a fixed centre pin.
/// The user pans the map to position the pin; the gem coordinate is the map
/// centre, read on every camera-idle. Existing gems render for context.
class PlacementScreen extends StatefulWidget {
  /// Optional starting centre — used when returning from the details step via
  /// "edit location" so the previously chosen point is restored.
  final double? initialLat;
  final double? initialLng;

  const PlacementScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';

  double? _lat;
  double? _lng;
  bool _hintVisible = true;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  List<MapMarkerData> _markersFor(List<Gem> gems) => gems
      .map((g) => MapMarkerData(
            id: g.id,
            lat: g.latitude!,
            lng: g.longitude!,
            emoji: g.emoji,
            icon: GemCategories.iconFor(g.category),
          ))
      .toList();

  // Centre the placement map on the user's current location. The fixed centre
  // pin reads the coordinate via onCameraIdle once the fly settles, so the gem
  // point ends up at the user's location without any extra wiring.
  Future<void> _goToCurrentLocation(MapEngineController c) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      c.flyTo(pos.latitude, pos.longitude, 14);
    } catch (_) {
      // Location unavailable — leave the map at its default centre.
    }
  }

  void _confirm() {
    if (_lat == null || _lng == null) return;
    // Slide the details form up as a bottom sheet over the placement map.
    showDropGemSheet(context, lat: _lat!, lng: _lng!);
  }

  @override
  Widget build(BuildContext context) {
    final gems = context.watch<GemProvider>().mappableGems;
    final hasCoord = _lat != null && _lng != null;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          // ── Live map ──
          MapEngineView(
            markers: _markersFor(gems),
            styleId: 'dark-v11',
            token: _token,
            onMarkerTap: (_) {},
            onReady: (c) {
              // On web the pin is painted inside the map container (zero lag);
              // on native we use the Flutter overlay widget below.
              if (kIsWeb) c.setCenterPin(true);
              if (hasCoord) {
                // Returning from "edit location": restore the prior point.
                c.flyTo(_lat!, _lng!, 12);
              } else {
                // Fresh drop: start at the user's current location so the pin
                // is already near where they are.
                _goToCurrentLocation(c);
              }
            },
            // Placement only needs the centre under the fixed pin; the bounds
            // (w/s/e/n) drive the discovery deck elsewhere and are ignored here.
            onCameraIdle: (lat, lng, w, s, e, n) {
              setState(() {
                _lat = lat;
                _lng = lng;
              });
            },
          ),

          // ── Fixed centre pin ──
          // On web the pin is drawn inside the map container by the GL JS
          // bridge (see explorifeMapSetCenterPin) so it composites with the
          // map canvas and never lags. On native we paint it as a Flutter
          // overlay, which stays in sync because flutter_map renders in-tree.
          if (!kIsWeb)
            IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lift the pin so its tip sits on the exact centre.
                    Transform.translate(
                      offset: const Offset(0, -20),
                      child: const Icon(Icons.location_on,
                          size: 44, color: AppTheme.primary),
                    ),
                    // Ground shadow ellipse under the tip.
                    Container(
                      width: 14,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Back button ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: _RoundBtn(
                  icon: Icons.arrow_back,
                  onTap: () =>
                      context.canPop() ? context.pop() : context.go('/explore'),
                ),
              ),
            ),
          ),

          // ── Dismissable hint banner ──
          if (_hintVisible)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(72, 14, 16, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEAD9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Drag the map to position your gem',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF993C1D),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _hintVisible = false),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.close,
                                size: 18, color: Color(0xFF993C1D)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom confirm button ──
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasCoord)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Text(
                          '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: hasCoord ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          disabledBackgroundColor:
                              AppTheme.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Confirm location',
                            style: GoogleFonts.dmSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF1A1A1A), size: 22),
      ),
    );
  }
}

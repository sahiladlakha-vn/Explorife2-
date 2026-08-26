import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/theme/app_theme.dart';

/// Opened when a city is tapped in the "Where to next?" destination browser
/// (destination_browser_sheet.dart) — an intermediate browsing page before
/// trip creation, not a jump straight into the wizard anymore.
///
/// Content is real Mapbox Tilequery data (name, category, real distance)
/// with NO price/rating/review-count/deal chrome — none of that exists
/// anywhere in this app (confirmed before building: no affiliate/booking
/// partner integration, Mapbox has no commerce data). Faking those numbers
/// the way `explore_screen_widgets.dart`'s hash-derived rating placeholder
/// does was explicitly ruled out. "Things to do" vs "Attractions" is a
/// best-effort local split on Mapbox's own POI category string — there's no
/// authoritative "this is a tourist attraction" flag to key off, so treat
/// the grouping as a reasonable heuristic, not a guarantee.
class DestinationLandingScreen extends StatefulWidget {
  const DestinationLandingScreen({
    super.key,
    required this.cityName,
    this.lat,
    this.lng,
  });

  final String cityName;
  final double? lat;
  final double? lng;

  @override
  State<DestinationLandingScreen> createState() =>
      _DestinationLandingScreenState();
}

enum _DestTab { explore, thingsToDo, transport, hotels }

extension on _DestTab {
  String get label => switch (this) {
        _DestTab.explore => 'Explore',
        _DestTab.thingsToDo => 'Things to do',
        _DestTab.transport => 'Transport',
        _DestTab.hotels => 'Hotels',
      };
}

class _DestinationLandingScreenState extends State<DestinationLandingScreen> {
  final MapboxTilequeryService _tilequery = MapboxTilequeryService();
  _DestTab _tab = _DestTab.explore;
  List<NearbyPoi> _pois = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lat = widget.lat, lng = widget.lng;
    if (lat == null || lng == null) {
      // No resolved coordinates (geocoding failed upstream) — nothing to
      // query nearby; show the empty state rather than erroring.
      setState(() => _loading = false);
      return;
    }
    final pois =
        await _tilequery.nearby(lat, lng, radiusMeters: 5000, limit: 30);
    if (mounted)
      setState(() {
        _pois = pois;
        _loading = false;
      });
  }

  // Best-effort local split on Mapbox's own category string — see class doc.
  static bool _looksLikeAttraction(String? category) {
    if (category == null) return false;
    final c = category.toLowerCase();
    const attractionHints = [
      'historic',
      'landmark',
      'museum',
      'park',
      'monument',
      'memorial',
      'place_of_worship',
      'viewpoint',
      'zoo',
      'aquarium',
      'art',
      'temple',
    ];
    return attractionHints.any(c.contains);
  }

  List<NearbyPoi> get _attractions =>
      _pois.where((p) => _looksLikeAttraction(p.category)).toList();
  List<NearbyPoi> get _thingsToDo =>
      _pois.where((p) => !_looksLikeAttraction(p.category)).toList();

  void _planTrip(BuildContext context) {
    final uri = Uri(path: '/trips/new', queryParameters: {
      'location': widget.cityName,
      if (widget.lat != null) 'lat': '${widget.lat}',
      if (widget.lng != null) 'lng': '${widget.lng}',
    });
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        foregroundColor: AppTheme.lightInk,
        elevation: 0,
        title: Text(widget.cityName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _TabRow(
            active: _tab,
            cityName: widget.cityName,
            onSelect: (t) => setState(() => _tab = t),
          ),
        ),
      ),
      body: _tab == _DestTab.explore
          ? _buildExplore(context)
          : _buildComingSoon(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _planTrip(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('+ Plan a trip to ${widget.cityName}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_empty,
                size: 36, color: AppTheme.lightMute),
            const SizedBox(height: 12),
            Text('${_tab.label} for ${widget.cityName} is coming soon.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.lightMute)),
          ],
        ),
      ),
    );
  }

  Widget _buildExplore(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_pois.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No places found near ${widget.cityName} yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.lightMute)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_thingsToDo.isNotEmpty)
          _PoiSection(
            title: 'Top things to do in ${widget.cityName}',
            seeAllLabel:
                'See ${_thingsToDo.length} things to do in ${widget.cityName}',
            pois: _thingsToDo.take(10).toList(),
          ),
        if (_attractions.isNotEmpty)
          _PoiSection(
            title: 'Top attractions in ${widget.cityName}',
            seeAllLabel:
                'See ${_attractions.length} attractions in ${widget.cityName}',
            pois: _attractions.take(10).toList(),
          ),
      ],
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow(
      {required this.active, required this.cityName, required this.onSelect});

  final _DestTab active;
  final String cityName;
  final ValueChanged<_DestTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final t in _DestTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: GestureDetector(
                onTap: () => onSelect(t),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      t == _DestTab.explore ? 'Explore $cityName' : t.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            active == t ? FontWeight.w700 : FontWeight.w500,
                        color: active == t
                            ? AppTheme.lightInk
                            : AppTheme.lightMute,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 2,
                      width: 24,
                      color:
                          active == t ? AppTheme.primary : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PoiSection extends StatelessWidget {
  const _PoiSection(
      {required this.title, required this.seeAllLabel, required this.pois});

  final String title;
  final String seeAllLabel;
  final List<NearbyPoi> pois;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lightInk)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: pois.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _PoiCard(poi: pois[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(seeAllLabel,
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PoiCard extends StatelessWidget {
  const _PoiCard({required this.poi});

  final NearbyPoi poi;

  void _comingSoonSave(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving places is coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/gems/poi', extra: poi),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      // Mapbox's POI data has no photo field at all (confirmed
                      // against the raw Tilequery response) — a category-specific
                      // icon on a tinted tile stands in, using Mapbox's own
                      // `maki` glyph name to pick something more specific than a
                      // generic pin.
                      child: Container(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        alignment: Alignment.center,
                        child: Icon(NearbyPoi.iconForMaki(poi.maki),
                            size: 30, color: AppTheme.primary),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _comingSoonSave(context),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.favorite_border,
                            size: 14, color: AppTheme.lightMute),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (poi.category != null)
                    Text(poi.category!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(poi.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.lightInk)),
                  if (poi.distanceMeters != null) ...[
                    const SizedBox(height: 4),
                    Text('${poi.distanceMeters!.round()}m away',
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

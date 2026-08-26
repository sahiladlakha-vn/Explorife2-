import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../providers/gem_provider.dart';
import '../../widgets/app_network_image.dart';

class GemDetailScreen extends StatefulWidget {
  /// A real saved_gems row id — fetched from GemProvider/the DB. Mutually
  /// exclusive with [poi].
  final String? id;

  /// A Mapbox-sourced point of interest (e.g. tapped from a destination
  /// landing page's "Top things to do" card) — rendered directly, no DB
  /// fetch at all, since it has no saved_gems row. Mutually exclusive with
  /// [id].
  final NearbyPoi? poi;

  const GemDetailScreen({super.key, required this.id}) : poi = null;
  const GemDetailScreen.fromPoi({super.key, required this.poi}) : id = null;

  @override
  State<GemDetailScreen> createState() => _GemDetailScreenState();
}

class _GemDetailScreenState extends State<GemDetailScreen> {
  Gem? _gem;
  List<NearbyPoi> _nearby = [];
  bool _loading = true;

  final PageController _photoController = PageController();
  int _photoIndex = 0;

  final MapboxTilequeryService _tilequery = MapboxTilequeryService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  /// Builds a transient, never-persisted Gem straight from a Mapbox POI —
  /// no DB fetch, since Mapbox places don't have a saved_gems row. Leaves
  /// every field the app has no real data for (description, tagline,
  /// difficulty, bestTimeToVisit, photos) null/empty rather than fabricating
  /// content — the UI already hides each of those sections when absent.
  Gem _gemFromPoi(NearbyPoi poi) => Gem(
        id: 'poi:${poi.lat},${poi.lng}',
        gemName: poi.name,
        category: poi.category,
        latitude: poi.lat,
        longitude: poi.lng,
        savedAt: DateTime.now(),
        maki: poi.maki,
        isFromPoi: true,
      );

  Future<void> _load() async {
    Gem? gem;
    if (widget.poi != null) {
      gem = _gemFromPoi(widget.poi!);
    } else {
      final prov = context.read<GemProvider>();
      final cached = prov.allGems.where((g) => g.id == widget.id).firstOrNull;
      gem = cached ?? await prov.fetchById(widget.id!);
    }
    if (gem == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    List<NearbyPoi> nearby = const [];
    if (gem.hasCoords) {
      nearby = await _tilequery.nearby(gem.latitude!, gem.longitude!,
          radiusMeters: 800, limit: 12);
      // Tilequery has no notion of "this exact place" to exclude — drop
      // anything suspiciously close (< 15m) so the gem itself doesn't show
      // up in its own "Nearby Experiences" rail.
      nearby = nearby.where((p) => (p.distanceMeters ?? 999) > 15).toList();
    }
    if (mounted) {
      setState(() {
        _gem = gem;
        _nearby = nearby;
        _loading = false;
      });
    }
  }

  void _jumpToPhoto(int i) {
    setState(() => _photoIndex = i);
    _photoController.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _openDirections(Gem gem) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${gem.latitude},${gem.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _share(Gem gem) {
    Clipboard.setData(
        ClipboardData(text: 'Check out "${gem.gemName}" on Explorife!'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied!')),
    );
  }

  // A POI-derived gem has no saved_gems row, so there's nothing for
  // gem_saves to reference — same "coming soon" message the POI's own card
  // already shows for its bookmark icon (destination_landing_screen.dart's
  // _PoiCard), rather than attempting a real save that would just fail.
  void _comingSoonSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving places is coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.lightSurface,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_gem == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface),
        body: Center(
            child: Text('Gem not found',
                style: GoogleFonts.fredoka(color: AppTheme.lightMute))),
      );
    }

    final gem = _gem!;
    final photos = gem.allPhotos;
    final prov = context.watch<GemProvider>();

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _photoGallery(
              gem,
              photos,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/explore'),
              onShare: () => _share(gem),
              isSaved: !gem.isFromPoi && prov.isSaved(gem.id),
              onToggleSave: gem.isFromPoi
                  ? _comingSoonSave
                  : () => context.read<GemProvider>().toggleSave(gem),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + difficulty
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text('${gem.emoji}  ${gem.displayCategory}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: AppTheme.primary)),
                    ),
                    if (gem.difficulty != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.lightCard,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(gem.difficulty!,
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11, color: AppTheme.lightMute)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),

                  Text(gem.gemName,
                      style: GoogleFonts.bebasNeue(
                          fontSize: 36,
                          color: AppTheme.lightInk,
                          letterSpacing: 0.5)),
                  if (gem.gemLocation != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.lightMute),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(gem.gemLocation!,
                            style: GoogleFonts.fredoka(
                                fontSize: 13, color: AppTheme.lightMute)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 20),

                  if (gem.description != null) ...[
                    Text('About',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 20,
                            letterSpacing: 0.5,
                            color: AppTheme.lightInk)),
                    const SizedBox(height: 8),
                    Text(gem.description!,
                        style: GoogleFonts.fredoka(
                            fontSize: 14,
                            color: AppTheme.lightMute,
                            height: 1.6)),
                    const SizedBox(height: 20),
                  ],

                  if (gem.bestTimeToVisit != null) ...[
                    _InfoTile(
                        icon: Icons.wb_sunny_outlined,
                        label: 'Best Time',
                        value: gem.bestTimeToVisit!),
                    const SizedBox(height: 20),
                  ],

                  if (gem.hasCoords) ...[
                    _LocationSection(gem: gem),
                    const SizedBox(height: 14),
                    _GetDirectionsButton(onTap: () => _openDirections(gem)),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
          if (_nearby.isNotEmpty)
            SliverToBoxAdapter(child: _NearbyExperiences(pois: _nearby)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Photo gallery: back/share/save row + hero + "X of Y" counter, all over
  // the hero photo (so they scroll away with it, per the reference), plus a
  // thumbnail strip below. Degrades to a plain single photo (no counter, no
  // strip) when there's 0-1 photos, which is every gem today (see
  // Gem.allPhotos) — never fabricates extra slots.
  Widget _photoGallery(
    Gem gem,
    List<String> photos, {
    required VoidCallback onBack,
    required VoidCallback onShare,
    required bool isSaved,
    required VoidCallback onToggleSave,
  }) {
    final hasGallery = photos.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photos.isEmpty)
                Container(
                  color: AppTheme.lightCard,
                  child: Center(
                    // A POI-derived gem carries Mapbox's own Maki icon —
                    // the same specific glyph (building, parking, etc.) its
                    // card already shows — instead of the generic pin emoji
                    // a catalogue gem with no photo falls back to.
                    child: gem.maki != null
                        ? Icon(NearbyPoi.iconForMaki(gem.maki),
                            size: 64, color: AppTheme.lightMute)
                        : Text(gem.emoji, style: const TextStyle(fontSize: 64)),
                  ),
                )
              else if (hasGallery)
                PageView.builder(
                  controller: _photoController,
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _photoIndex = i),
                  itemBuilder: (_, i) => AppNetworkImage(
                      url: photos[i], semanticLabel: gem.gemName),
                )
              else
                AppNetworkImage(url: photos.first, semanticLabel: gem.gemName),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HeaderIcon(icon: Icons.arrow_back, onTap: onBack),
                      Row(children: [
                        _HeaderIcon(icon: Icons.share_outlined, onTap: onShare),
                        const SizedBox(width: 8),
                        _HeaderIcon(
                          icon:
                              isSaved ? Icons.bookmark : Icons.bookmark_outline,
                          onTap: onToggleSave,
                          iconColor: isSaved ? AppTheme.primary : Colors.white,
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              if (hasGallery)
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${_photoIndex + 1} of ${photos.length}',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 12, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
        if (hasGallery)
          Container(
            color: AppTheme.lightSurface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final sel = i == _photoIndex;
                return GestureDetector(
                  onTap: () => _jumpToPhoto(i),
                  child: Container(
                    width: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? AppTheme.primary : Colors.transparent,
                          width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AppNetworkImage(url: photos[i]),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  const _HeaderIcon(
      {required this.icon, required this.onTap, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _LocationSection extends StatelessWidget {
  final Gem gem;
  const _LocationSection({required this.gem});

  @override
  Widget build(BuildContext context) {
    final overlay = GeocodingService.buildStaticMapOverlay(pins: [
      (lat: gem.latitude!, lng: gem.longitude!, label: '', color: 'FF6B35'),
    ]);
    final mapUrl = GeocodingService.staticImageUrl(
      lat: gem.latitude!,
      lng: gem.longitude!,
      zoom: 14,
      width: 600,
      height: 300,
      styleId: 'dark-v11',
      overlay: overlay,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location',
            style: GoogleFonts.bebasNeue(
                fontSize: 20, letterSpacing: 0.5, color: AppTheme.lightInk)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: mapUrl != null
                ? AppNetworkImage(
                    url: mapUrl, semanticLabel: 'Map of ${gem.gemName}')
                : Container(color: AppTheme.lightCard),
          ),
        ),
      ],
    );
  }
}

class _GetDirectionsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GetDirectionsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.directions_outlined, size: 18),
        label: Text('Get Directions',
            style:
                GoogleFonts.fredoka(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.lightMute)),
          Text(value,
              style:
                  GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
        ]),
      ]),
    );
  }
}

/// Real nearby POIs (any category — cafes, viewpoints, landmarks...) around
/// this gem's coordinates, via the same [MapboxTilequeryService] the
/// destination landing page's "Nearby" section already uses. Mapbox Tilequery
/// never returns a photo for any result (confirmed against the raw API
/// response), so each card shows a category icon on a tinted tile instead of
/// a fabricated image.
class _NearbyExperiences extends StatelessWidget {
  final List<NearbyPoi> pois;
  const _NearbyExperiences({required this.pois});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Nearby Experiences',
                style: GoogleFonts.bebasNeue(
                    fontSize: 20,
                    letterSpacing: 0.5,
                    color: AppTheme.lightInk)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: pois.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _NearbyCard(poi: pois[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final NearbyPoi poi;
  const _NearbyCard({required this.poi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Container(
                color: AppTheme.primary.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(NearbyPoi.iconForMaki(poi.maki),
                    size: 26, color: AppTheme.primary),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name,
                    style: GoogleFonts.fredoka(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (poi.distanceMeters != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    poi.distanceMeters! < 1000
                        ? '${poi.distanceMeters!.round()} m'
                        : '${(poi.distanceMeters! / 1000).toStringAsFixed(1)} km',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: AppTheme.lightMute),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

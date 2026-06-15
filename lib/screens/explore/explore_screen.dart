import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

enum _MapStyle { outdoors, dark, satellite }

class _ExploreScreenState extends State<ExploreScreen> {
  final MapController _mapController = MapController();
  Gem? _selected;
  _MapStyle _style = _MapStyle.outdoors;
  bool _mapReady = false;

  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';

  // Material glyphs per gem category — emoji don't render in CanvasKit (web).
  static const Map<String, IconData> _gemIcons = {
    'hiking': Icons.hiking,
    'camping': Icons.cabin,
    'viewpoint': Icons.photo_camera,
    'food': Icons.restaurant,
    'temple': Icons.account_balance,
    'cave': Icons.landscape,
    'coastal': Icons.water,
    'nature': Icons.park,
  };

  IconData _iconFor(String? cat) => _gemIcons[cat] ?? Icons.place;

  String get _styleId {
    switch (_style) {
      case _MapStyle.dark:
        return 'dark-v11';
      case _MapStyle.satellite:
        return 'satellite-streets-v12';
      case _MapStyle.outdoors:
        return 'outdoors-v12';
    }
  }

  String get _tileUrl {
    if (_token.isEmpty) {
      // Fallback to free CARTO basemaps when no Mapbox token is configured.
      return _style == _MapStyle.dark
          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
          : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
    }
    return 'https://api.mapbox.com/styles/v1/mapbox/$_styleId/tiles/256/{z}/{x}/{y}@2x?access_token=$_token';
  }

  @override
  Widget build(BuildContext context) {
    final gemProv = context.watch<GemProvider>();
    final gems = gemProv.mappableGems;

    return Scaffold(
      body: Stack(
        children: [
          // ── MAP ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(10.776, 106.700), // Ho Chi Minh City
              initialZoom: 11,
              minZoom: 3,
              maxZoom: 18,
              onTap: (_, __) => setState(() => _selected = null),
              onMapReady: () {
                _mapReady = true;
                _fitToGems(gems);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.explorife.app',
                tileSize: 256,
              ),
              MarkerLayer(markers: gems.map(_buildMarker).toList()),
            ],
          ),

          // ── TOP: menu + search ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _SquareBtn(
                    icon: Icons.menu,
                    onTap: () => _showMenu(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.go('/search'),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Color(0xFF8A8A8A), size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Search gems, cities, vibes…',
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                color: const Color(0xFF8A8A8A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── RIGHT CONTROL STACK ──
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.30,
            child: Column(
              children: [
                _MapControl(
                  child: Column(
                    children: [
                      _IconHit(icon: Icons.add, onTap: () => _zoom(1)),
                      Container(width: 26, height: 1, color: AppTheme.divider),
                      _IconHit(icon: Icons.remove, onTap: () => _zoom(-1)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MapControl(
                  child: _IconHit(
                    icon: Icons.my_location,
                    color: AppTheme.primary,
                    onTap: _locateMe,
                  ),
                ),
                const SizedBox(height: 12),
                _MapControl(
                  child: _IconHit(
                    icon: _style == _MapStyle.dark
                        ? Icons.wb_sunny_outlined
                        : Icons.dark_mode_outlined,
                    color: const Color(0xFF4FC3F7),
                    onTap: () => setState(() => _style =
                        _style == _MapStyle.dark ? _MapStyle.outdoors : _MapStyle.dark),
                  ),
                ),
                const SizedBox(height: 12),
                _MapControl(
                  child: _IconHit(
                    icon: Icons.layers_outlined,
                    onTap: () => _showLayers(context),
                  ),
                ),
              ],
            ),
          ),

          // ── ADD GEM FAB ──
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height * 0.30 + 16,
            child: GestureDetector(
              onTap: () => context.go('/drop-gem'),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
            ),
          ),

          // ── SELECTED GEM (floating, just above the sheet) ──
          if (_selected != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.30 + 12,
              child: _GemCard(
                gem: _selected!,
                icon: _iconFor(_selected!.category),
                onTap: () => context.go('/gems/${_selected!.id}'),
                onClose: () => setState(() => _selected = null),
              ),
            ),

          // ── BOTTOM SHEET ──
          _BottomSheet(
            gemProv: gemProv,
            iconFor: _iconFor,
            onGemTap: (g) {
              setState(() => _selected = g);
              if (g.hasCoords && _mapReady) {
                _mapController.move(LatLng(g.latitude!, g.longitude!), 13);
              }
              context.go('/gems/${g.id}');
            },
          ),

          // ── LOADING ──
          if (gemProv.loading)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.30,
              left: 0,
              right: 0,
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  // ───────── helpers ─────────

  void _zoom(double delta) {
    final cam = _mapController.camera;
    _mapController.move(cam.center, (cam.zoom + delta).clamp(3, 18));
  }

  void _fitToGems(List<Gem> gems) {
    if (gems.isEmpty || !_mapReady) return;
    final pts = gems.map((g) => LatLng(g.latitude!, g.longitude!)).toList();
    if (pts.length == 1) {
      _mapController.move(pts.first, 13);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(60, 120, 60, 280),
      ),
    );
  }

  Future<void> _locateMe() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _fitToGems(context.read<GemProvider>().mappableGems);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (_mapReady) _mapController.move(LatLng(pos.latitude, pos.longitude), 13);
    } catch (_) {
      if (mounted) _fitToGems(context.read<GemProvider>().mappableGems);
    }
  }

  void _showLayers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final s in _MapStyle.values)
              ListTile(
                leading: Icon(
                  s == _MapStyle.outdoors
                      ? Icons.terrain
                      : s == _MapStyle.dark
                          ? Icons.dark_mode
                          : Icons.satellite_alt,
                  color: _style == s ? AppTheme.primary : AppTheme.textSecondary,
                ),
                title: Text(
                  s == _MapStyle.outdoors
                      ? 'Outdoors'
                      : s == _MapStyle.dark
                          ? 'Dark'
                          : 'Satellite',
                  style: GoogleFonts.dmSans(
                    color: _style == s ? AppTheme.primary : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: _style == s
                    ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                    : null,
                onTap: () {
                  setState(() => _style = s);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _menuTile(context, Icons.add_location_alt_outlined, 'Drop a Gem', '/drop-gem'),
            _menuTile(context, Icons.menu_book_outlined, 'Stories', '/stories'),
            _menuTile(context, Icons.receipt_long_outlined, 'Splits', '/splits'),
            _menuTile(context, Icons.person_outline, 'Profile', '/profile'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(BuildContext context, IconData icon, String label, String route) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary),
      title: Text(label,
          style: GoogleFonts.dmSans(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
    );
  }

  Marker _buildMarker(Gem g) {
    final isSelected = _selected?.id == g.id;
    return Marker(
      point: LatLng(g.latitude!, g.longitude!),
      width: 46,
      height: 46,
      child: GestureDetector(
        onTap: () {
          setState(() => _selected = g);
          if (_mapReady) {
            _mapController.move(LatLng(g.latitude!, g.longitude!), _mapController.camera.zoom);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : AppTheme.primary,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? AppTheme.primary : Colors.black).withOpacity(0.4),
                blurRadius: isSelected ? 14 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            _iconFor(g.category),
            size: 20,
            color: isSelected ? Colors.white : AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// SMALL CONTROLS
// ─────────────────────────────────────────
class _SquareBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SquareBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  final Widget child;
  const _MapControl({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconHit extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _IconHit({required this.icon, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────
// BOTTOM SHEET
// ─────────────────────────────────────────
class _BottomSheet extends StatelessWidget {
  final GemProvider gemProv;
  final IconData Function(String?) iconFor;
  final ValueChanged<Gem> onGemTap;
  const _BottomSheet({
    required this.gemProv,
    required this.iconFor,
    required this.onGemTap,
  });

  int _count(String cat) => cat == 'all'
      ? gemProv.allGems.length
      : gemProv.allGems.where((g) => g.category == cat).length;

  @override
  Widget build(BuildContext context) {
    final gems = gemProv.gems;
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.14,
      maxChildSize: 0.82,
      snap: true,
      snapSizes: const [0.30, 0.82],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -6)),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HIDDEN GEMS',
                                  style: GoogleFonts.bebasNeue(
                                    fontSize: 30,
                                    color: const Color(0xFF111111),
                                    letterSpacing: 0.5,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_count('all')} hidden spots · tap to explore',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: const Color(0xFF8A8A8A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'LIVE',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Filter chips
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          _FilterChip(
                            icon: Icons.auto_awesome,
                            label: 'All Gems',
                            count: _count('all'),
                            selected: gemProv.selectedCategory == 'all',
                            onTap: () => context.read<GemProvider>().selectCategory('all'),
                          ),
                          ...Gem.categories.map((cat) => _FilterChip(
                                icon: iconFor(cat),
                                label: cat[0].toUpperCase() + cat.substring(1),
                                count: _count(cat),
                                selected: gemProv.selectedCategory == cat,
                                onTap: () =>
                                    context.read<GemProvider>().selectCategory(cat),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Gem carousel
              if (gems.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 190,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: gems.length,
                      itemBuilder: (_, i) => _CarouselCard(
                        gem: gems[i],
                        icon: iconFor(gems[i].category),
                        onTap: () => onGemTap(gems[i]),
                      ),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No gems in this category yet.',
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: const Color(0xFF8A8A8A)),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFF333333);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFE2E2E2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppTheme.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withOpacity(0.25) : const Color(0xFFE2E2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  final Gem gem;
  final IconData icon;
  final VoidCallback onTap;
  const _CarouselCard({required this.gem, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = gem.photoUrl ?? 'https://picsum.photos/seed/${gem.id}/400/300';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEDED)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: img,
                    width: 170,
                    height: 105,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: const Color(0xFFEDEDED)),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFEDEDED),
                      child: const Icon(Icons.image_not_supported_outlined,
                          color: Color(0xFFBBBBBB)),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                gem.gemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111111),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 12, color: Color(0xFF8A8A8A)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      gem.gemLocation ?? gem.displayCategory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: const Color(0xFF8A8A8A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// SELECTED GEM CARD
// ─────────────────────────────────────────
class _GemCard extends StatelessWidget {
  final Gem gem;
  final IconData icon;
  final VoidCallback onTap, onClose;
  const _GemCard({
    required this.gem,
    required this.icon,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(gem.gemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111111))),
              if (gem.gemLocation != null)
                Text(gem.gemLocation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: const Color(0xFF8A8A8A))),
            ]),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, color: Color(0xFF8A8A8A), size: 18),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: AppTheme.primary, size: 22),
        ]),
      ),
    );
  }
}

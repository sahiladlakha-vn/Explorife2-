import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final MapController _mapController = MapController();
  Gem? _selected;

  @override
  Widget build(BuildContext context) {
    final gemProv = context.watch<GemProvider>();
    final gems = gemProv.mappableGems;
    final selectedCat = gemProv.selectedCategory;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(14.0, 108.0),
              initialZoom: 5.5,
              onTap: (_, __) => setState(() => _selected = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.explorife.app',
              ),
              MarkerLayer(
                markers: gems.map((g) => _buildMarker(g)).toList(),
              ),
            ],
          ),

          // Top bar
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => context.go('/search'),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(23),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Row(children: [
                              const SizedBox(width: 14),
                              const Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                              const SizedBox(width: 8),
                              Text('Search gems...', style: GoogleFonts.dmSans(
                                fontSize: 14, color: AppTheme.textSecondary)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => context.go('/drop-gem'),
                        child: Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(23),
                          ),
                          child: const Icon(Icons.add_location_alt_outlined, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),

                // Category pills
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _CategoryChip(
                        label: 'ALL',
                        emoji: '🗺️',
                        selected: selectedCat == 'all',
                        onTap: () => context.read<GemProvider>().selectCategory('all'),
                      ),
                      ...Gem.categories.map((cat) => _CategoryChip(
                        label: cat.toUpperCase(),
                        emoji: Gem.categoryEmoji[cat] ?? '📍',
                        selected: selectedCat == cat,
                        onTap: () => context.read<GemProvider>().selectCategory(cat),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Gem count badge
          Positioned(
            top: 130,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                '${gems.length} gems',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ),

          // Selected gem card
          if (_selected != null)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _GemCard(
                gem: _selected!,
                onTap: () => context.go('/gems/${_selected!.id}'),
                onClose: () => setState(() => _selected = null),
              ),
            ),

          // Loading
          if (gemProv.loading)
            const Positioned(
              top: 130,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
        ],
      ),
    );
  }

  Marker _buildMarker(Gem g) {
    final isSelected = _selected?.id == g.id;
    return Marker(
      point: LatLng(g.latitude!, g.longitude!),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => setState(() => _selected = g),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.divider,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? AppTheme.primary : Colors.black).withOpacity(0.4),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(g.emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label, emoji;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.emoji, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          )),
        ]),
      ),
    );
  }
}

class _GemCard extends StatelessWidget {
  final Gem gem;
  final VoidCallback onTap, onClose;
  const _GemCard({required this.gem, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child: Center(child: Text(gem.emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(gem.gemName, style: GoogleFonts.dmSans(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              if (gem.gemLocation != null)
                Text(gem.gemLocation!, style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(gem.displayCategory, style: GoogleFonts.jetBrainsMono(
                    fontSize: 9, color: AppTheme.primary)),
                ),
                if (gem.difficulty != null) ...[
                  const SizedBox(width: 6),
                  Text(gem.difficulty!, style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ]),
            ]),
          ),
          Column(children: [
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 18),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.chevron_right, color: AppTheme.primary, size: 20),
          ]),
        ]),
      ),
    );
  }
}

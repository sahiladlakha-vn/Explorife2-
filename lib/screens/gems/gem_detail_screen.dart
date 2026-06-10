import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../providers/gem_provider.dart';

class GemDetailScreen extends StatefulWidget {
  final String id;
  const GemDetailScreen({super.key, required this.id});

  @override
  State<GemDetailScreen> createState() => _GemDetailScreenState();
}

class _GemDetailScreenState extends State<GemDetailScreen> {
  Gem? _gem;
  List<Gem> _related = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prov = context.read<GemProvider>();
    // try cache first
    final cached = prov.allGems.where((g) => g.id == widget.id).firstOrNull;
    if (cached != null) {
      final related = await prov.fetchRelated(cached.category ?? '', cached.id);
      if (mounted) setState(() { _gem = cached; _related = related; _loading = false; });
      return;
    }
    final gem = await prov.fetchById(widget.id);
    if (gem != null) {
      final related = await prov.fetchRelated(gem.category ?? '', gem.id);
      if (mounted) setState(() { _gem = gem; _related = related; _loading = false; });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_gem == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(backgroundColor: AppTheme.bg),
        body: Center(child: Text('Gem not found', style: GoogleFonts.dmSans(color: AppTheme.textSecondary))),
      );
    }

    final gem = _gem!;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: gem.photoUrl != null ? 280 : 120,
            pinned: true,
            backgroundColor: AppTheme.bg,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, size: 18),
              ),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: gem.photoUrl != null
                  ? Stack(fit: StackFit.expand, children: [
                      Image.network(gem.photoUrl!, fit: BoxFit.cover),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppTheme.bg],
                            stops: [0.5, 1.0],
                          ),
                        ),
                      ),
                    ])
                  : Container(
                      color: AppTheme.surface,
                      child: Center(
                        child: Text(gem.emoji, style: const TextStyle(fontSize: 64)),
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Category + difficulty
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                    ),
                    child: Text('${gem.emoji}  ${gem.displayCategory}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.primary)),
                  ),
                  if (gem.difficulty != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(gem.difficulty!,
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary)),
                    ),
                  ],
                ]),
                const SizedBox(height: 12),

                Text(gem.gemName, style: GoogleFonts.bebasNeue(
                    fontSize: 36, color: AppTheme.textPrimary, letterSpacing: 0.5)),
                if (gem.gemLocation != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(gem.gemLocation!, style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppTheme.textSecondary)),
                  ]),
                ],
                const SizedBox(height: 20),

                if (gem.description != null) ...[
                  Text('About', style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text(gem.description!, style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppTheme.textSecondary, height: 1.6)),
                  const SizedBox(height: 20),
                ],

                if (gem.bestTimeToVisit != null) ...[
                  _InfoTile(icon: Icons.wb_sunny_outlined, label: 'Best Time', value: gem.bestTimeToVisit!),
                  const SizedBox(height: 12),
                ],

                // Mini map
                if (gem.hasCoords) ...[
                  Text('Location', style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 200,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(gem.latitude!, gem.longitude!),
                          initialZoom: 12,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.explorife.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(gem.latitude!, gem.longitude!),
                              width: 44, height: 44,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(child: Text(gem.emoji, style: const TextStyle(fontSize: 18))),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Related gems
                if (_related.isNotEmpty) ...[
                  Text('More ${gem.displayCategory} Gems',
                      style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _related.length,
                      itemBuilder: (ctx, i) {
                        final r = _related[i];
                        return GestureDetector(
                          onTap: () => context.go('/gems/${r.id}'),
                          child: Container(
                            width: 160,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.emoji, style: const TextStyle(fontSize: 20)),
                              const SizedBox(height: 6),
                              Text(r.gemName, style: GoogleFonts.dmSans(
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textPrimary)),
        ]),
      ]),
    );
  }
}

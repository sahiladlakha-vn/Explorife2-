import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/destination_provider.dart';
import '../../models/destination.dart';
import '../../core/layout/max_width_center.dart';

/// A real place-info page — name, address, Mapbox's own POI category, a
/// static map centered on it, and real nearby points of interest (via
/// Tilequery). Deliberately does NOT show price/"Book Now"/reviews/
/// amenities the way this screen used to: Mapbox has no data for any of
/// those, and fabricating them would just be swapping one kind of mock data
/// for another. [id] is a Mapbox `mapbox_id` from a DestinationProvider
/// search result, resolved here (not passed in already-resolved) because
/// `/suggest` results carry no coordinates — see Destination's doc comment.
class DestinationDetailScreen extends StatefulWidget {
  final String id;
  const DestinationDetailScreen({super.key, required this.id});

  @override
  State<DestinationDetailScreen> createState() => _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen> {
  final _tilequery = MapboxTilequeryService();

  Destination? _destination;
  List<NearbyPoi> _nearby = [];
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final destination = await context.read<DestinationProvider>().resolve(widget.id);
    if (!mounted) return;
    if (destination == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    setState(() {
      _destination = destination;
      _loading = false;
    });
    // Nearby POIs load separately and don't block showing the place itself —
    // an empty/failed Tilequery call just means no "Nearby" section renders.
    final pois = await _tilequery.nearby(destination.latitude, destination.longitude);
    if (mounted) setState(() => _nearby = pois);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_notFound || _destination == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppTheme.lightSurface),
        body: const Center(child: Text('Destination not found')),
      );
    }

    final d = _destination!;
    final heroUrl = GeocodingService.staticImageUrl(lat: d.latitude, lng: d.longitude, zoom: 14);

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, d, heroUrl),
          SliverToBoxAdapter(
              child: MaxWidthCenter(child: _buildBody(context, d))),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Destination d, String? heroUrl) {
    final provider = context.watch<DestinationProvider>();
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back, color: AppTheme.lightInk),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: () => provider.toggleSave(d.id),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(
              provider.isSaved(d.id) ? Icons.bookmark : Icons.bookmark_outline,
              color: provider.isSaved(d.id) ? AppTheme.primary : AppTheme.lightInk,
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        // A real static map centered on the place, not a stock/fake photo —
        // Mapbox has no photo data for arbitrary POIs, but it does have this.
        background: heroUrl != null
            ? Image.network(heroUrl, fit: BoxFit.cover)
            : Container(color: AppTheme.lightCard),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Destination d) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.name,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.lightInk)),
          if (d.placeFormatted.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: AppTheme.lightMute),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(d.placeFormatted,
                      style: const TextStyle(color: AppTheme.lightMute, fontSize: 15)),
                ),
              ],
            ),
          ],
          if (d.category != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(d.category!,
                  style: const TextStyle(
                      color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 28),
          const Text('Nearby',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.lightInk)),
          const SizedBox(height: 4),
          const Text('Real points of interest near this location.',
              style: TextStyle(color: AppTheme.lightMute, fontSize: 13)),
          const SizedBox(height: 12),
          if (_nearby.isEmpty)
            const Text('No nearby points of interest found.',
                style: TextStyle(color: AppTheme.lightMute, fontSize: 13))
          else
            ..._nearby.map((p) => _NearbyPoiTile(poi: p)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _NearbyPoiTile extends StatelessWidget {
  final NearbyPoi poi;
  const _NearbyPoiTile({required this.poi});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.place_outlined, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.lightInk)),
                if (poi.category != null)
                  Text(poi.category!,
                      style: const TextStyle(color: AppTheme.lightMute, fontSize: 12)),
              ],
            ),
          ),
          if (poi.distanceMeters != null)
            Text('${poi.distanceMeters!.round()}m',
                style: const TextStyle(color: AppTheme.lightMute, fontSize: 12)),
        ],
      ),
    );
  }
}

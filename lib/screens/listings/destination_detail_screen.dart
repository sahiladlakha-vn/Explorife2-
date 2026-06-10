import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/destination_provider.dart';
import '../../models/destination.dart';

class DestinationDetailScreen extends StatelessWidget {
  final String id;
  const DestinationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final destination = context.read<DestinationProvider>().findById(id);
    if (destination == null) {
      return const Scaffold(body: Center(child: Text('Destination not found')));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, destination),
          SliverToBoxAdapter(child: _buildBody(context, destination)),
        ],
      ),
      bottomNavigationBar: _buildBookingBar(context, destination),
    );
  }

  Widget _buildAppBar(BuildContext context, Destination d) {
    final provider = context.watch<DestinationProvider>();
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
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
              d.isSaved ? Icons.bookmark : Icons.bookmark_outline,
              color: d.isSaved ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Image.network(d.imageUrl, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Destination d) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: AppTheme.textSecondary),
                        Text(d.country,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text('${d.rating}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Text('${d.reviewCount} reviews',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: d.tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag,
                  style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
            )).toList(),
          ),
          const SizedBox(height: 20),
          const Text('About', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(d.description,
              style: const TextStyle(color: AppTheme.textSecondary, height: 1.6, fontSize: 14)),
          const SizedBox(height: 24),
          const Text('What\'s Included',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildAmenity(Icons.wifi, 'Free WiFi'),
          _buildAmenity(Icons.local_parking, 'Free Parking'),
          _buildAmenity(Icons.pool, 'Swimming Pool'),
          _buildAmenity(Icons.restaurant, 'Breakfast Included'),
          const SizedBox(height: 24),
          const Text('Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._sampleReviews.map((r) => _ReviewTile(review: r)),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildAmenity(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBookingBar(BuildContext context, Destination d) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('\$${d.pricePerNight.toInt()}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              const Text('per night',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking flow coming soon!')),
              ),
              child: const Text('Book Now'),
            ),
          ),
        ],
      ),
    );
  }

  static final _sampleReviews = [
    _ReviewData('Sarah K.', 'https://picsum.photos/seed/sarah/100/100', 5.0,
        'Absolutely breathtaking! One of the best trips of my life. The scenery was incredible.'),
    _ReviewData('James T.', 'https://picsum.photos/seed/james/100/100', 4.5,
        'Amazing experience. Would definitely recommend to any travel lover.'),
  ];
}

class _ReviewData {
  final String name, avatar, comment;
  final double rating;
  const _ReviewData(this.name, this.avatar, this.rating, this.comment);
}

class _ReviewTile extends StatelessWidget {
  final _ReviewData review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(review.avatar),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < review.rating ? Icons.star : Icons.star_border,
                        size: 12, color: Colors.amber,
                      )),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(review.comment,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

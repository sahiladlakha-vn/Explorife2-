import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/restaurant.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/restaurant_repository.dart';
import '../../widgets/state_views.dart';

/// The "Approve/reject business listings" queue for Restaurant — same
/// screen shape as AttractionModerationScreen (same permission row in
/// permissions.dart covers every business type, not a per-type
/// permission).
class RestaurantModerationScreen extends StatefulWidget {
  const RestaurantModerationScreen({super.key});

  @override
  State<RestaurantModerationScreen> createState() =>
      _RestaurantModerationScreenState();
}

class _RestaurantModerationScreenState extends State<RestaurantModerationScreen> {
  final _repo = RestaurantRepository();
  List<Restaurant> _pending = [];
  bool _loading = true;
  final Set<String> _acting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pending = await _repo.fetchPending();
    if (mounted) {
      setState(() {
        _pending = pending;
        _loading = false;
      });
    }
  }

  Future<void> _act(Restaurant restaurant, {required bool approve}) async {
    setState(() => _acting.add(restaurant.id));
    try {
      await _repo.verify(restaurant.id, approve: approve);
      if (!mounted) return;
      setState(() => _pending.removeWhere((r) => r.id == restaurant.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? '"${restaurant.name}" verified'
            : '"${restaurant.name}" rejected'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update listing: $e')),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(restaurant.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role;
    if (!role.isAdminTier) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface),
        body: Center(
          child: Text('Only Content Moderator, Regional Admin, or Super Admin '
              'accounts can review business listings.',
              textAlign: TextAlign.center,
              style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        title: const Text('Pending Listings'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _pending.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    EmptyStateView(
                        text: 'Nothing pending — all caught up.',
                        icon: Icons.check_circle_outline),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pending.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _PendingCard(
                      restaurant: _pending[i],
                      busy: _acting.contains(_pending[i].id),
                      onApprove: () => _act(_pending[i], approve: true),
                      onReject: () => _act(_pending[i], approve: false),
                    ),
                  ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.restaurant,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Restaurant restaurant;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.restaurant_outlined, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(restaurant.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.lightInk)),
            ),
            if (restaurant.gemId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('LINKED TO GEM',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.5, color: AppTheme.primary, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(restaurant.address,
              style: const TextStyle(color: AppTheme.lightMute, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
              '${restaurant.priceRange.wire} · ${restaurant.cuisineType.join(', ')}',
              style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onApprove,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

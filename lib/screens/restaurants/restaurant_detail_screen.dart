import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/restaurant.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/restaurant_repository.dart';
import '../../widgets/common/photo_carousel.dart';

/// Public-facing Restaurant view — mirrors AttractionDetailScreen's
/// structure exactly, including the RETRACTED-badge-visible-to-admins-too
/// fix applied proactively here (Attraction only got it after a second
/// review pass — see docs/audits/attraction-business-profile-2026-09-04.md's
/// "Post-review fix 2").
///
/// No rating/review UI here either — same reasoning as Attraction: this
/// app has no reviews/ratings feature anywhere yet.
class RestaurantDetailScreen extends StatefulWidget {
  const RestaurantDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  Restaurant? _restaurant;
  List<RestaurantMenuItem> _menuItems = [];
  bool _loading = true;
  bool _retracting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _confirmRetract(Restaurant restaurant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retract this listing?'),
        content: const Text(
            'Travellers will no longer see this listing. You can still view it '
            'yourself, but re-listing isn\'t available yet — this cannot be undone '
            'from this screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Retract')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _retracting = true);
    try {
      await RestaurantRepository().retract(restaurant.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not retract listing: $e')));
      }
    } finally {
      if (mounted) setState(() => _retracting = false);
    }
  }

  Future<void> _load() async {
    final restaurant = await RestaurantRepository().fetchById(widget.id);
    final menuItems = restaurant == null
        ? <RestaurantMenuItem>[]
        : await RestaurantRepository().fetchMenuItems(restaurant.id);
    if (mounted) {
      setState(() {
        _restaurant = restaurant;
        _menuItems = menuItems;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.lightSurface,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    final restaurant = _restaurant;
    if (restaurant == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface, elevation: 0),
        body: Center(
            child: Text('Listing not found',
                style: GoogleFonts.fredoka(color: AppTheme.lightMute))),
      );
    }

    final auth = context.watch<AuthProvider>();
    final userId = auth.user?.id;
    final isOwner = userId != null && userId == restaurant.ownerId;
    // Same reasoning as AttractionDetailScreen: an admin can reach this
    // screen for someone else's listing too via RLS's own admin SELECT
    // policy, and deserves to see the truth just as much as the owner.
    final canSeeRetractedBadge = isOwner || auth.role.isAdminTier;

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoCarousel(
              photos: restaurant.gallery,
              emptyIcon: Icons.restaurant_outlined,
              semanticLabel: restaurant.name,
              topLeft: _BackIcon(
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/explore'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(restaurant.name,
                          style: GoogleFonts.bebasNeue(
                              fontSize: 32, color: AppTheme.lightInk, letterSpacing: 0.5)),
                    ),
                    if (restaurant.verificationStatus ==
                        RestaurantVerificationStatus.verified)
                      const Icon(Icons.verified, color: AppTheme.primary, size: 22),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppTheme.lightMute),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(restaurant.address,
                          style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
                    ),
                  ]),
                  if (restaurant.cuisineType.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in restaurant.cuisineType)
                          Chip(
                            label: Text(c, style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppTheme.lightCard,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      _InfoCell(
                        icon: Icons.payments_outlined,
                        label: 'Price Range',
                        value: restaurant.priceRange.wire,
                      ),
                      _InfoCell(
                        icon: Icons.schedule,
                        label: 'Opening Hours',
                        value: restaurant.openingHours,
                      ),
                      _InfoCell(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: restaurant.phone,
                      ),
                      _InfoCell(
                        icon: Icons.event_seat_outlined,
                        label: 'Reservations',
                        value: restaurant.reservationOption
                            ? 'Accepted'
                            : 'Walk-ins only',
                      ),
                    ],
                  ),
                  if (restaurant.dietaryOptions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Dietary Options',
                        style: GoogleFonts.bebasNeue(fontSize: 18, color: AppTheme.lightInk)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in restaurant.dietaryOptions)
                          Chip(
                            label: Text(d, style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  if (_menuItems.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Menu Highlights',
                        style: GoogleFonts.bebasNeue(fontSize: 18, color: AppTheme.lightInk)),
                    const SizedBox(height: 8),
                    for (final item in _menuItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Expanded(
                            child: Text(item.dishName,
                                style: GoogleFonts.fredoka(
                                    fontSize: 14, color: AppTheme.lightInk)),
                          ),
                          Text('${item.currency} ${item.priceAmount}',
                              style: GoogleFonts.fredoka(
                                  fontSize: 13, color: AppTheme.lightMute)),
                        ]),
                      ),
                  ],
                  if (canSeeRetractedBadge && restaurant.isRetracted) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('RETRACTED — not visible to travellers',
                          style: TextStyle(
                              color: Colors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (isOwner) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await context.push('/restaurants/${restaurant.id}/edit',
                              extra: restaurant);
                          if (context.mounted) _load();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit listing'),
                      ),
                    ),
                    if (!restaurant.isRetracted) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _retracting ? null : () => _confirmRetract(restaurant),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          icon: _retracting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.remove_circle_outline, size: 16),
                          label: const Text('Retract listing'),
                        ),
                      ),
                    ],
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

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.lightMute)),
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fredoka(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.lightInk)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _BackIcon extends StatelessWidget {
  const _BackIcon({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attraction.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/attraction_repository.dart';
import '../../widgets/common/photo_carousel.dart';

/// Public-facing Attraction view — reached directly (e.g. from Gem
/// Detail's "View full listing" link) or on its own for a listing with no
/// linked Gem. Reuses [PhotoCarousel] (the same shared hero component Gem
/// Detail and Tour Detail already use) rather than a third gallery
/// implementation.
///
/// No rating/review UI here — see docs/audits/attraction-business-profile-
/// 2026-09-04.md: this app has no reviews/ratings feature anywhere yet
/// (Gems have none; Tour explicitly deferred them), so nothing here is
/// fabricated to fill that gap.
class AttractionDetailScreen extends StatefulWidget {
  const AttractionDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<AttractionDetailScreen> createState() => _AttractionDetailScreenState();
}

class _AttractionDetailScreenState extends State<AttractionDetailScreen> {
  Attraction? _attraction;
  bool _loading = true;
  bool _retracting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _confirmRetract(Attraction attraction) async {
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
      await AttractionRepository().retract(attraction.id);
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
    final attraction = await AttractionRepository().fetchById(widget.id);
    if (mounted) {
      setState(() {
        _attraction = attraction;
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
    final attraction = _attraction;
    if (attraction == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface, elevation: 0),
        body: Center(
            child: Text('Listing not found',
                style: GoogleFonts.fredoka(color: AppTheme.lightMute))),
      );
    }

    final userId = context.watch<AuthProvider>().user?.id;
    final isOwner = userId != null && userId == attraction.ownerId;

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoCarousel(
              photos: attraction.gallery,
              emptyIcon: Icons.attractions_outlined,
              semanticLabel: attraction.name,
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
                      child: Text(attraction.name,
                          style: GoogleFonts.bebasNeue(
                              fontSize: 32, color: AppTheme.lightInk, letterSpacing: 0.5)),
                    ),
                    if (attraction.verificationStatus ==
                        AttractionVerificationStatus.verified)
                      const Icon(Icons.verified, color: AppTheme.primary, size: 22),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppTheme.lightMute),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(attraction.address,
                          style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
                    ),
                  ]),
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
                        icon: Icons.confirmation_number_outlined,
                        label: 'Entry Fee',
                        value: attraction.isFree
                            ? 'Free'
                            : '${attraction.currency} ${attraction.entryFeeAmount}',
                      ),
                      _InfoCell(
                        icon: Icons.schedule,
                        label: 'Opening Hours',
                        value: attraction.openingHours,
                      ),
                      if (attraction.recommendedDuration != null &&
                          attraction.recommendedDuration!.isNotEmpty)
                        _InfoCell(
                          icon: Icons.hourglass_empty,
                          label: 'Recommended Duration',
                          value: attraction.recommendedDuration!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('About',
                      style: GoogleFonts.bebasNeue(fontSize: 18, color: AppTheme.lightInk)),
                  const SizedBox(height: 8),
                  Text(attraction.description,
                      style: GoogleFonts.fredoka(
                          fontSize: 14, color: AppTheme.lightMute, height: 1.5)),
                  if (isOwner && attraction.isRetracted) ...[
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
                          await context.push('/attractions/${attraction.id}/edit',
                              extra: attraction);
                          if (context.mounted) _load();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit listing'),
                      ),
                    ),
                    if (!attraction.isRetracted) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _retracting ? null : () => _confirmRetract(attraction),
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

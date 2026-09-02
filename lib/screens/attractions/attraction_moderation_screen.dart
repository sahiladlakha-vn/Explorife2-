import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attraction.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/attraction_repository.dart';
import '../../widgets/state_views.dart';

/// The "Approve/reject business listings" queue from the permissions
/// matrix — Content Moderator, Regional Admin, and Super Admin can all
/// reach this (see permissions.dart's `Permission.approveRejectBusinessListings`
/// row); anyone else sees an honest denial rather than a query that just
/// happens to come back empty via RLS.
class AttractionModerationScreen extends StatefulWidget {
  const AttractionModerationScreen({super.key});

  @override
  State<AttractionModerationScreen> createState() =>
      _AttractionModerationScreenState();
}

class _AttractionModerationScreenState extends State<AttractionModerationScreen> {
  final _repo = AttractionRepository();
  List<Attraction> _pending = [];
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

  Future<void> _act(Attraction attraction, {required bool approve}) async {
    setState(() => _acting.add(attraction.id));
    try {
      await _repo.verify(attraction.id, approve: approve);
      if (!mounted) return;
      setState(() => _pending.removeWhere((a) => a.id == attraction.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? '"${attraction.name}" verified'
            : '"${attraction.name}" rejected'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update listing: $e')),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(attraction.id));
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
                      attraction: _pending[i],
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
    required this.attraction,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Attraction attraction;
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
            Icon(GemCategories.iconFor(attraction.category),
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(attraction.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.lightInk)),
            ),
            if (attraction.gemId != null)
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
          Text(attraction.address,
              style: const TextStyle(color: AppTheme.lightMute, fontSize: 12)),
          const SizedBox(height: 8),
          Text(attraction.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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

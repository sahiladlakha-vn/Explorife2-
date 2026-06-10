import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/hike.dart';
import '../../providers/auth_provider.dart';
import '../../providers/hike_provider.dart';

class HikesScreen extends StatefulWidget {
  const HikesScreen({super.key});

  @override
  State<HikesScreen> createState() => _HikesScreenState();
}

class _HikesScreenState extends State<HikesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) {
        context.read<HikeProvider>().fetchHikes(auth.user!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HikeProvider>();
    final auth = context.watch<AuthProvider>();
    final hikes = prov.hikes;

    // Stats
    final totalKm = hikes.fold(0.0, (s, h) => s + (h.distanceKm ?? 0));
    final totalSecs = hikes.fold(0, (s, h) => s + (h.durationSeconds ?? 0));
    final totalEle = hikes.fold(0.0, (s, h) => s + (h.elevationGainM ?? 0));

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bg,
            title: Text('MY HIKES',
                style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => context.go('/log-hike'),
              ),
            ],
          ),

          // Stats row
          if (hikes.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(children: [
                  _StatCell(value: '${totalKm.toStringAsFixed(1)}km', label: 'DISTANCE'),
                  Container(width: 1, height: 40, color: AppTheme.divider),
                  _StatCell(
                    value: _formatDuration(totalSecs),
                    label: 'TIME',
                  ),
                  Container(width: 1, height: 40, color: AppTheme.divider),
                  _StatCell(
                    value: '${totalEle.toInt()}m',
                    label: 'ELEVATION',
                  ),
                ]),
              ),
            ),

          if (prov.loading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: AppTheme.primary)),
              ),
            )
          else if (!auth.isAuthenticated)
            SliverToBoxAdapter(
              child: _EmptyState(
                emoji: '🔒',
                title: 'Sign in to track hikes',
                action: 'Sign In',
                onAction: () => context.go('/auth?redirect=/hikes'),
              ),
            )
          else if (hikes.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyState(
                emoji: '🥾',
                title: 'No hikes logged yet',
                action: 'Log Your First Hike',
                onAction: () => context.go('/log-hike'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _HikeCard(hike: hikes[i]),
                  childCount: hikes.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: auth.isAuthenticated
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/log-hike'),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Log Hike',
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: GoogleFonts.bebasNeue(fontSize: 22, color: AppTheme.primary)),
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 9, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        ]),
      );
}

class _HikeCard extends StatelessWidget {
  final HikeTrack hike;
  const _HikeCard({required this.hike});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: Text(hike.emoji, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hike.title,
                style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              if (hike.distanceKm != null) ...[
                const Icon(Icons.straighten, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text('${hike.distanceKm!.toStringAsFixed(1)} km',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.schedule, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 3),
              Text(hike.durationFormatted,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary)),
              if (hike.elevationGainM != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.trending_up, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text('↑${hike.elevationGainM!.toInt()}m',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ]),
          ]),
        ),
        Text(
          '${hike.startedAt.day}/${hike.startedAt.month}',
          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji, title, action;
  final VoidCallback onAction;
  const _EmptyState(
      {required this.emoji, required this.title, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.bebasNeue(
                  fontSize: 22, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text(action,
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

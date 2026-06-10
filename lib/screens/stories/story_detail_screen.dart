import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';

class StoryDetailScreen extends StatefulWidget {
  final String id;
  const StoryDetailScreen({super.key, required this.id});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  Story? _story;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prov = context.read<StoryProvider>();
    final cached = prov.allStories.where((s) => s.id == widget.id).firstOrNull;
    if (cached != null) {
      if (mounted) setState(() { _story = cached; _loading = false; });
      return;
    }
    final story = await prov.fetchById(widget.id);
    if (mounted) setState(() { _story = story; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_story == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(backgroundColor: AppTheme.bg),
        body: Center(
          child: Text('Story not found',
              style: GoogleFonts.dmSans(color: AppTheme.textSecondary)),
        ),
      );
    }

    final s = _story!;
    final readMinutes = ((s.body.length / 5) / 200).ceil().clamp(1, 99);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          // Hero
          SliverAppBar(
            expandedHeight: s.hasPhoto ? 300 : 120,
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
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share_outlined, size: 18),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'Check out "${s.title}" on Explorife!'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied!')),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: s.hasPhoto
                  ? Stack(fit: StackFit.expand, children: [
                      Image.network(s.photo, fit: BoxFit.cover),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppTheme.bg],
                            stops: [0.4, 1.0],
                          ),
                        ),
                      ),
                    ])
                  : Container(color: AppTheme.surface),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Meta row
                Row(children: [
                  if (s.adventureType != null) ...[
                    Text(s.typeEmoji_, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      child: Text(s.adventureType!,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (s.featured)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('⭐ FEATURED',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: Colors.amber)),
                    ),
                ]),
                const SizedBox(height: 12),

                // Title
                Text(s.title,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 36, color: AppTheme.textPrimary, letterSpacing: 0.5,
                        height: 1.05)),
                const SizedBox(height: 12),

                // Author / location / read time
                Wrap(spacing: 16, runSpacing: 6, children: [
                  _MetaChip(icon: Icons.person_outline, label: s.displayAuthor),
                  if (s.location != null)
                    _MetaChip(icon: Icons.location_on_outlined, label: s.location!),
                  _MetaChip(icon: Icons.schedule_outlined, label: '$readMinutes min read'),
                  if (s.difficulty != null)
                    _MetaChip(icon: Icons.terrain_outlined, label: s.difficulty!),
                ]),
                const SizedBox(height: 20),

                Divider(color: AppTheme.divider),
                const SizedBox(height: 16),

                // Story body
                if (s.body.isNotEmpty)
                  Text(s.body,
                      style: GoogleFonts.dmSans(
                          fontSize: 15, color: AppTheme.textPrimary,
                          height: 1.75, letterSpacing: 0.1))
                else if (s.excerpt != null)
                  Text(s.excerpt!,
                      style: GoogleFonts.dmSans(
                          fontSize: 15, color: AppTheme.textSecondary, height: 1.75)),

                const SizedBox(height: 24),

                // Reality box
                if (s.lonelinessLevel != null || s.safetyLevel != null)
                  _RealityBox(story: s),

                // Tags
                if (s.tags.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: s.tags.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Text('#$t',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: AppTheme.textSecondary)),
                    )).toList(),
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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppTheme.textSecondary),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textSecondary)),
    ]);
  }
}

class _RealityBox extends StatelessWidget {
  final Story story;
  const _RealityBox({required this.story});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('REALITY CHECK',
            style: GoogleFonts.bebasNeue(fontSize: 18, color: AppTheme.primary, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        if (story.lonelinessLevel != null)
          _RealityRow(
            label: 'Loneliness',
            value: '${story.lonelinessLevel}/5',
            icon: Icons.people_outline,
          ),
        if (story.safetyLevel != null)
          _RealityRow(
            label: 'Safety',
            value: story.safetyLevel!,
            icon: Icons.shield_outlined,
          ),
        if (story.connectivity != null)
          _RealityRow(
            label: 'Connectivity',
            value: story.connectivity!,
            icon: Icons.signal_cellular_alt_outlined,
          ),
        if (story.aftermath != null)
          _RealityRow(
            label: 'Emotional aftermath',
            value: story.aftermath!,
            icon: Icons.psychology_outlined,
          ),
      ]),
    );
  }
}

class _RealityRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _RealityRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 15, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textSecondary)),
        Text(value,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

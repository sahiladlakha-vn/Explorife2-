import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/hike.dart';
import '../../providers/auth_provider.dart';
import '../../providers/hike_provider.dart';

class SplitsScreen extends StatefulWidget {
  const SplitsScreen({super.key});
  @override
  State<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends State<SplitsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) {
        context.read<HikeProvider>().fetchGroups(auth.user!.id);
      }
    });
  }

  void _showCreateGroup() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('NEW TRIP GROUP',
              style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. Vietnam Road Trip 2025',
              hintStyle: GoogleFonts.dmSans(
                  color: AppTheme.textSecondary.withOpacity(0.5)),
              filled: true,
              fillColor: AppTheme.surface2,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.divider)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.divider)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                final auth = context.read<AuthProvider>();
                Navigator.pop(ctx);
                await context.read<HikeProvider>().createGroup(
                    userId: auth.user!.id, name: ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text('CREATE',
                  style: GoogleFonts.bebasNeue(fontSize: 18, letterSpacing: 0.5)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HikeProvider>();
    final auth = context.watch<AuthProvider>();
    final groups = prov.groups;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bg,
            title: Text('EXPENSE SPLITS',
                style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
            actions: [
              if (auth.isAuthenticated)
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _showCreateGroup),
            ],
          ),

          if (!auth.isAuthenticated)
            SliverToBoxAdapter(
              child: _empty('🔒', 'Sign in to split costs',
                  action: 'Sign In',
                  onTap: () => context.go('/auth?redirect=/splits')),
            )
          else if (groups.isEmpty)
            SliverToBoxAdapter(
              child: _empty('💸', 'No trip groups yet',
                  action: 'Create a Group',
                  onTap: _showCreateGroup),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _GroupCard(
                      group: groups[i],
                      onTap: () => context.go('/splits/${groups[i].id}')),
                  childCount: groups.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: auth.isAuthenticated
          ? FloatingActionButton.extended(
              onPressed: _showCreateGroup,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: Text('New Group',
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  Widget _empty(String emoji, String label,
      {required String action, required VoidCallback onTap}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(label,
              style: GoogleFonts.bebasNeue(
                  fontSize: 22, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text(action,
                style: GoogleFonts.dmSans(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final SplitGroup group;
  final VoidCallback onTap;
  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            child: const Center(
                child: Text('💸', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.name,
                  style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              if (group.description != null)
                Text(group.description!,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppTheme.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ]),
      ),
    );
  }
}

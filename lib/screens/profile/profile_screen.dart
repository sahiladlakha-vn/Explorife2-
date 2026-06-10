import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/destination_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isAuthenticated) {
      return _SignInPrompt();
    }

    final user = auth.user!;
    final saved = context.watch<DestinationProvider>().saved;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppTheme.bg,
            title: Text('Profile', style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
            actions: [
              IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () {}),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF1a1008), Color(0xFF0f0a05)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    // Avatar
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 3),
                      ),
                      child: ClipOval(
                        child: user.avatarUrl != null
                            ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                            : Container(
                                color: AppTheme.primary.withOpacity(0.2),
                                child: Center(
                                  child: Text(
                                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'E',
                                    style: GoogleFonts.bebasNeue(fontSize: 32, color: AppTheme.primary),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(user.name, style: GoogleFonts.bebasNeue(fontSize: 24, color: AppTheme.textPrimary, letterSpacing: 0.5)),
                    if (user.email != null)
                      Text(user.email!, style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary)),
                    if (user.provider != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'via ${user.provider}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Stats
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  bottom: BorderSide(color: AppTheme.divider),
                  top: BorderSide(color: AppTheme.divider),
                ),
              ),
              child: Row(
                children: [
                  _StatTile(value: '0', label: 'TRIPS'),
                  Container(width: 1, height: 40, color: AppTheme.divider),
                  _StatTile(value: '0', label: 'GEMS'),
                  Container(width: 1, height: 40, color: AppTheme.divider),
                  _StatTile(value: '${saved.length}', label: 'SAVED'),
                ],
              ),
            ),
          ),

          // Saved destinations strip
          if (saved.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Text('SAVED', style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/listings'),
                      child: Text('SEE ALL →', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.primary)),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: saved.length,
                  itemBuilder: (ctx, i) {
                    final d = saved[i];
                    return GestureDetector(
                      onTap: () => context.go('/listings/${d.id}'),
                      child: Container(
                        width: 120, margin: const EdgeInsets.only(right: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(d.imageUrl, fit: BoxFit.cover),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                                ),
                              ),
                            ),
                            Positioned(bottom: 8, left: 8, right: 8,
                              child: Text(d.name,
                                  style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11))),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // Menu
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: Column(
                children: [
                  _MenuItem(icon: '🗺️', label: 'My Trips', onTap: () => context.go('/hikes')),
                  _MenuItem(icon: '💎', label: 'My Gems', onTap: () => context.go('/explore')),
                  _MenuItem(icon: '📖', label: 'My Stories', onTap: () => context.go('/stories')),
                  _MenuItem(icon: '💸', label: 'Expense Splits', onTap: () => context.go('/splits')),
                  _MenuItem(icon: '🔔', label: 'Notifications', onTap: () {}),
                  _MenuItem(icon: '⚙️', label: 'Settings', onTap: () {}),
                  _MenuItem(
                    icon: '🚪',
                    label: 'Sign Out',
                    danger: true,
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: Text('Sign Out', style: GoogleFonts.bebasNeue(fontSize: 22)),
                        content: Text('Are you sure?', style: GoogleFonts.dmSans(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.read<AuthProvider>().signOut();
                            },
                            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🧗', style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              Text('JOIN THE TRIBE', style: GoogleFonts.bebasNeue(fontSize: 32, color: AppTheme.textPrimary, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your profile, save gems, track hikes, and connect with fellow adventurers.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/auth?redirect=/profile'),
                  child: const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  const _StatTile({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Text(value, style: GoogleFonts.bebasNeue(fontSize: 24, color: AppTheme.primary)),
          Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  final bool danger;
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.divider))),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: danger ? Colors.red.withOpacity(0.1) : AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: danger ? Colors.red : AppTheme.textPrimary)),
          const Spacer(),
          if (!danger) Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ]),
      ),
    );
  }
}

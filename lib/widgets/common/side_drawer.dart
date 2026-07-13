import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_provider.dart';

// ─────────────────────────────────────────
// SIDE DRAWER (slides in from the left)
//
// Orange profile header + a NAVIGATE quick-action grid + a MY ACCOUNT list.
// Pulls the signed-in user's name / avatar / handle from AuthProvider; falls
// back to sensible placeholders when signed out. Shared across the app shell
// so the same panel opens from the Home avatar, the Profile tab and the map
// menu button.
// ─────────────────────────────────────────
class SideDrawer extends StatelessWidget {
  const SideDrawer({super.key});

  void _go(BuildContext context, String route) {
    Navigator.of(context).pop(); // close the drawer first
    context.go(route);
  }

  void _confirmSignOut(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Sign Out',
            style: GoogleFonts.bebasNeue(
                fontSize: 22, color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.dmSans(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<BookingProvider>().clear();
              context.read<AuthProvider>().signOut();
              context.go('/home');
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final name = user?.name ?? 'Explorer';
    final handle = _handleFor(user?.email, name);
    final avatarUrl = user?.avatarUrl;
    final width = MediaQuery.of(context).size.width * 0.82;

    return SizedBox(
      width: width,
      child: Drawer(
        backgroundColor: AppTheme.bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Orange profile header ──
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF7A33), Color(0xFFFF5A1F)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Avatar(url: avatarUrl, name: name),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bebasNeue(
                          fontSize: 28,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          height: 1.05,
                        ),
                      ),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => _go(context, '/profile'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Profile',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward,
                                  size: 14, color: AppTheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Scrollable body ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                children: [
                  _sectionLabel('NAVIGATE'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NavCard(
                          icon: Icons.map_outlined,
                          color: AppTheme.primary,
                          label: 'Explore Map',
                          onTap: () => _go(context, '/explore'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.menu_book_outlined,
                          color: const Color(0xFF4F9CF9),
                          label: 'Stories',
                          onTap: () => _go(context, '/stories'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NavCard(
                          icon: Icons.public,
                          color: const Color(0xFF2EC27E),
                          label: 'Destinations',
                          onTap: () => _go(context, '/listings'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.diamond_outlined,
                          color: const Color(0xFF9B6DFF),
                          label: 'Drop a Gem',
                          onTap: () => _go(context, '/drop-gem'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _sectionLabel('MY ACCOUNT'),
                  const SizedBox(height: 8),
                  _AccountTile(
                    icon: Icons.bookmark_border,
                    title: 'Saved Gems',
                    subtitle: 'Your bookmarked spots',
                    onTap: () => _go(context, '/profile'),
                  ),
                  _AccountTile(
                    icon: Icons.menu_book_outlined,
                    title: 'My Stories',
                    subtitle: 'Stories you submitted',
                    onTap: () => _go(context, '/stories'),
                  ),
                  _AccountTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Splits',
                    subtitle: 'Expense groups',
                    onTap: () => _go(context, '/splits'),
                  ),
                  _AccountTile(
                    icon: Icons.groups_outlined,
                    title: 'Travel Crew',
                    subtitle: 'Your explorer network',
                    badge: 'SOON',
                    enabled: false,
                  ),
                  _AccountTile(
                    icon: Icons.download_outlined,
                    title: 'Offline Maps',
                    subtitle: 'Download for offline use',
                    badge: 'PRO',
                    enabled: false,
                  ),
                  _AccountTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Account & privacy',
                    onTap: () => _go(context, '/profile'),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => _confirmSignOut(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout,
                              size: 18, color: Color(0xFFFF6B6B)),
                          const SizedBox(width: 8),
                          Text(
                            'Sign Out',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFF6B6B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _handleFor(String? email, String name) {
    if (email != null && email.contains('@')) {
      return '@${email.split('@').first}';
    }
    return '@${name.toLowerCase().replaceAll(RegExp(r'\s+'), '.')}';
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF777777),
          letterSpacing: 1.5,
        ),
      );
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w[0])
            .join()
            .toUpperCase();
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _initialsLabel(initials),
              errorWidget: (_, __, ___) => _initialsLabel(initials),
            )
          : _initialsLabel(initials),
    );
  }

  Widget _initialsLabel(String initials) => Center(
        child: Text(
          initials,
          style: GoogleFonts.dmSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _NavCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool enabled;
  final VoidCallback? onTap;
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? AppTheme.textPrimary : const Color(0xFF6A6A6A);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badge == 'PRO'
                                ? AppTheme.primary.withValues(alpha: 0.16)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: badge == 'PRO'
                                  ? AppTheme.primary
                                  : const Color(0xFF999999),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF8A8A8A),
                    ),
                  ),
                ],
              ),
            ),
            if (enabled)
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }
}

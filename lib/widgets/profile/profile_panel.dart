import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gem_provider.dart';
import '../../providers/trip_provider.dart';
import '../app_network_image.dart';
import '../auth/sign_in_sheet.dart';
import 'confirm_sign_out.dart';
import 'edit_profile_sheet.dart';

/// Desktop/tablet's right-side slide-in profile panel — AppShell's mirror
/// of the hamburger drawer (SideNav), just anchored to the right edge and
/// triggered by the top bar's avatar instead of the hamburger. AppShell
/// owns the open/closed state, the slide transition, and the scrim, same
/// as it does for SideNav; this widget is just the panel's content, which
/// branches on real auth status:
///
/// - Guest (including signed-out, which shouldn't happen once a session
///   exists — see AuthProvider._init): mounts [SignInPromptContent] — the
///   EXACT SAME widget the contextual sign-in bottom sheet
///   (requireAccount/SignInSheet) and the mobile Profile tab's guest state
///   (_SignInPrompt) use. One sign-in UI, three trigger points, not three
///   near-duplicate screens.
/// - Real account: avatar/name/role badge, a Trips/Saved stat row (both
///   from real provider state — TripProvider.trips/GemProvider.savedGems),
///   and links to My Trips/Saved Gems/Edit Profile/Settings/Help & Support/
///   Sign Out. No Reviews stat — there's no reviews feature anywhere in
///   this app yet (TravellerProfileRepository.fetchReviewsWritten always
///   returns const []), so showing one here would be a permanent, fake 0.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.onClose,
    required this.closeFocusNode,
  });

  final VoidCallback onClose;
  final FocusNode closeFocusNode;

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isGuest = !auth.isAuthenticated || (auth.user?.isGuest ?? true);

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppTheme.lightSurface,
        border: Border(left: BorderSide(color: AppTheme.lightBorder)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(-6, 0)),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Account',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 17, color: AppTheme.lightInk)),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        focusNode: closeFocusNode,
                        onTap: onClose,
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close,
                              size: 20, color: AppTheme.lightMute),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.lightBorder),
            Expanded(
              child: isGuest
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: SignInPromptContent(
                        action: 'open_profile',
                        onDismiss: onClose,
                      ),
                    )
                  : _SignedInPanelContent(onClose: onClose),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInPanelContent extends StatefulWidget {
  const _SignedInPanelContent({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_SignedInPanelContent> createState() => _SignedInPanelContentState();
}

class _SignedInPanelContentState extends State<_SignedInPanelContent> {
  @override
  void initState() {
    super.initState();
    // Guarded/idempotent inside the provider (a no-op once loaded) — same
    // convention ProfileScreen's own mount hook already relies on. Needed
    // here too since this panel can be opened without ever having visited
    // the full Profile screen first, and the SAVED stat below needs
    // savedGems actually hydrated to read as anything but a misleading 0.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<GemProvider>().loadSaved());
  }

  void _goToProfileTab(BuildContext context, int tab) {
    widget.onClose();
    context.go('/profile?tab=$tab');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    final tripsCount = context.watch<TripProvider>().trips.length;
    final savedCount = context.watch<GemProvider>().savedGems.length;
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  border: Border.all(color: AppTheme.lightBorder),
                ),
                child: ClipOval(
                  child: hasAvatar
                      ? AppNetworkImage(url: user.avatarUrl!, fit: BoxFit.cover)
                      : Center(
                          child: Text(initial,
                              style: GoogleFonts.bebasNeue(
                                  fontSize: 28, color: AppTheme.primary)),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(user.name,
                  style: GoogleFonts.bebasNeue(
                      fontSize: 20, color: AppTheme.lightInk)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Text(user.role.label.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppTheme.primary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _Stat(value: '$tripsCount', label: 'TRIPS')),
            Container(width: 1, height: 32, color: AppTheme.lightBorder),
            Expanded(child: _Stat(value: '$savedCount', label: 'SAVED')),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, color: AppTheme.lightBorder),
        const SizedBox(height: 8),
        _PanelLink(
          icon: Icons.map_outlined,
          label: 'My Trips',
          onTap: () => _goToProfileTab(context, 1),
        ),
        _PanelLink(
          icon: Icons.bookmark_outline,
          label: 'Saved Gems',
          onTap: () => _goToProfileTab(context, 2),
        ),
        _PanelLink(
          icon: Icons.person_outline,
          label: 'Edit Profile',
          onTap: () {
            widget.onClose();
            showEditProfileSheet(context);
          },
        ),
        _PanelLink(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: () => _goToProfileTab(context, 5),
        ),
        _PanelLink(
          icon: Icons.help_outline,
          label: 'Help & Support',
          // Matches Settings' own "Help & support" row (currently a stub
          // there too) — an honest coming-soon beats a dead tap with no
          // feedback at all.
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Help & support is coming soon')),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppTheme.lightBorder),
        const SizedBox(height: 8),
        _PanelLink(
          icon: Icons.logout,
          label: 'Sign Out',
          danger: true,
          onTap: () {
            widget.onClose();
            confirmSignOut(context);
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style:
                GoogleFonts.bebasNeue(fontSize: 22, color: AppTheme.primary)),
        Text(label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9, color: AppTheme.lightMute, letterSpacing: 0.5)),
      ],
    );
  }
}

class _PanelLink extends StatelessWidget {
  const _PanelLink({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : AppTheme.lightInk;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.fredoka(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
                if (!danger)
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.lightMute),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

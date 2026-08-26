part of '../profile_screen.dart';

// Fixed chrome above the tab body: header, avatar, stats bar, tab bar.

/// Two soft accent blobs behind the header/stats block — pure decoration,
/// giving the glass stats bar something colourful to actually reveal (a
/// blur over a flat fill just looks like a flat fill). Cheap: a RadialGradient
/// already fades to nothing on its own, no BackdropFilter needed here.
class _ChromeGlow extends StatelessWidget {
  const _ChromeGlow();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: -50,
            top: -70,
            child: _blob(220, AppTheme.primary),
          ),
          Positioned(
            right: -60,
            top: -80,
            child: _blob(210, _kGreen),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ),
        ),
      );
}

// ─────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────
class _Header extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final String? memberSince;
  const _Header({
    required this.user,
    required this.onMenu,
    required this.onSettings,
    required this.onSignOut,
    required this.memberSince,
  });

  String get _handle {
    if (user.email != null && user.email!.contains('@')) {
      return '@${user.email!.split('@').first}';
    }
    return '@${user.name.toLowerCase().replaceAll(RegExp(r"\s+"), '.')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _GlassIconButton(icon: Icons.menu, onTap: onMenu),
                const Spacer(),
                _GlassIconButton(icon: Icons.settings_outlined, onTap: onSettings),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: Icons.logout,
                  iconColor: const Color(0xFFFF6B6B),
                  onTap: onSignOut,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(user: user),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.bebasNeue(
                                fontSize: 22,
                                color: AppTheme.lightInk,
                                letterSpacing: 0.3,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.13),
                              border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('MEMBER',
                                style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppTheme.primary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: AppTheme.lightInk.withValues(alpha: 0.55),
                        ),
                      ),
                      if (memberSince != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          memberSince!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: AppTheme.lightInk.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular glass button — translucent blurred fill, matching the
/// stats bar's glass language. Used for the header's menu/settings/sign-out
/// actions in place of bare icons.
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  const _GlassIconButton({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            ),
            child: Icon(icon, size: 18, color: iconColor ?? AppTheme.lightInk),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AuthUser user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.lightSurface, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: user.avatarUrl != null
                ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary,
                          Color.lerp(AppTheme.primary, Colors.white, 0.35)!,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        user.name.isNotEmpty
                            ? user.name[0].toUpperCase()
                            : 'E',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 24, color: Colors.white),
                      ),
                    ),
                  ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.lightSurface, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  /// [gems] is the count of SAVED gems (bookmarks), not dropped pins. [alerts]
  /// is the active trip's derived-alert count; null means there is no active
  /// trip, which renders as an em-dash rather than a misleading "0".
  final int gems, trips;
  final int? alerts;
  final double spent;
  final bool loading;
  const _StatsBar({
    required this.gems,
    required this.trips,
    required this.alerts,
    required this.spent,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlerts = alerts != null && alerts! > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            ),
            child: Row(
              children: [
                _cell('$trips', 'TRIPS', _kInk),
                _divider(),
                _cell('$gems', 'SAVED', AppTheme.primary),
                _divider(),
                _cell(loading ? '··' : '\$${spent.toStringAsFixed(0)}',
                    'SPLIT SPEND', _kTeal),
                _divider(),
                _cell(alerts == null ? '–' : '$alerts', 'ALERTS',
                    hasAlerts ? _kWarn : _kInk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: _kBorder.withValues(alpha: 0.7));

  Widget _cell(String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.bebasNeue(
                    fontSize: 30, color: color, height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: _kMute, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// TAB BAR
// ─────────────────────────────────────────
/// Floating segmented control — one pill background, a single sliding
/// highlight behind whichever tab is active (AnimatedPositioned, driven by
/// [active]'s index), rather than N independently-coloured chips.
class _TabBar extends StatelessWidget {
  final List<String> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  const _TabBar(
      {required this.tabs, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _kStripe,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kBorder),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabW = constraints.maxWidth / tabs.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: tabW * active,
                  top: 0,
                  bottom: 0,
                  width: tabW,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary,
                          Color.lerp(AppTheme.primary, Colors.white, 0.18)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: tabs.asMap().entries.map((e) {
                    final i = e.key;
                    final isActive = i == active;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onSelect(i),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            e.value,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fredoka(
                              fontSize: 12.5,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive ? Colors.white : _kMute,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

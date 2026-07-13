part of '../profile_screen.dart';

// Fixed chrome above the tab body: header, avatar, stats bar, tab bar.

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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_headerTop, _headerBottom],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Menu button
              GestureDetector(
                onTap: onMenu,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.menu, color: Color(0xFF1A1A1A)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(user: user),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
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
                                    fontSize: 32,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.7)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          if (memberSince != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              memberSince!,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: onSettings,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Icon(Icons.settings_outlined,
                              size: 20, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: onSignOut,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.red.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.logout,
                                  size: 15, color: Color(0xFFFF6B6B)),
                              const SizedBox(width: 6),
                              Text(
                                'Out',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
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
                ],
              ),
            ],
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
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6B4A2F), width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: user.avatarUrl != null
                ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                : Container(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    child: Center(
                      child: Text(
                        user.name.isNotEmpty
                            ? user.name[0].toUpperCase()
                            : 'E',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 40, color: AppTheme.primary),
                      ),
                    ),
                  ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(color: _headerBottom, width: 3),
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
    return Container(
      color: _kStripe,
      child: Row(
        children: [
          _cell('$gems', 'SAVED', AppTheme.primary),
          _divider(),
          _cell('$trips', 'TRIPS', _kInk),
          _divider(),
          _cell(alerts == null ? '–' : '$alerts', 'ALERTS', _kInk),
          _divider(),
          _cell(loading ? '··' : '\$${spent.toStringAsFixed(0)}', 'SPLIT SPEND',
              _kTeal),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 44, color: _kBorder);

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
class _TabBar extends StatelessWidget {
  final List<(IconData, String)> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  const _TabBar(
      {required this.tabs, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final i = e.key;
            final isActive = i == active;
            final color = isActive ? AppTheme.primary : _kMute;
            return GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppTheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(e.value.$1, size: 20, color: color),
                    const SizedBox(height: 5),
                    Text(
                      e.value.$2,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

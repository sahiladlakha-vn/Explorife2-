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
        color: AppTheme.lightSurface,
        border: Border(bottom: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onMenu,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.menu,
                          color: AppTheme.lightInk.withValues(alpha: 0.9)),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onSettings,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.settings_outlined,
                          size: 20,
                          color: AppTheme.lightInk.withValues(alpha: 0.8)),
                    ),
                  ),
                  GestureDetector(
                    onTap: onSignOut,
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.logout,
                          size: 19, color: Color(0xFFFF6B6B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                            Icon(Icons.edit_outlined,
                                size: 14,
                                color: AppTheme.lightInk.withValues(alpha: 0.55)),
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
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6B4A2F), width: 2),
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
                            fontSize: 24, color: AppTheme.primary),
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
    return Container(
      color: _kStripe,
      child: Row(
        children: [
          _cell('$trips', 'TRIPS', _kInk),
          _divider(),
          _cell('$gems', 'SAVED', AppTheme.primary),
          _divider(),
          _cell(loading ? '··' : '\$${spent.toStringAsFixed(0)}', 'SPLIT SPEND',
              _kTeal),
          _divider(),
          _cell(alerts == null ? '–' : '$alerts', 'ALERTS', _kInk),
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
  final List<String> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  const _TabBar(
      {required this.tabs, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kStripe,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final i = e.key;
            final isActive = i == active;
            return GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: isActive ? AppTheme.primary : _kBorder),
                ),
                child: Text(
                  e.value,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : _kMute,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

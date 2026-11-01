part of '../profile_screen.dart';

// Fixed chrome above the tab body: header, avatar, stats bar, tab bar.
//
// This block used to also render `_ChromeGlow` — two soft RadialGradient
// blobs positioned behind the header/stats — as pure decoration. Removed:
// it was the only gradient-blob decoration anywhere in the app (every other
// "glass" surface uses a flat frosted blur, no colored glow) and conveyed no
// information, per the redesign brief's "decorative, adds visual noise"
// call. If `_kGreen` (profile_palette.dart) is now unused elsewhere, that's
// expected — it was introduced for this blob.

// ─────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────
class _Header extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final String? memberSince;
  // Desktop-only (item 7 of the 2026-09-18 full-viewport redesign): the
  // stats bar rendered inline next to the name/handle instead of
  // ProfileScreen stacking a separate full-width _StatsBar row beneath this
  // header. Null on mobile, where that separate row is kept unchanged.
  final Widget? stats;
  const _Header({
    required this.user,
    required this.onMenu,
    required this.onSettings,
    required this.onSignOut,
    required this.memberSince,
    this.stats,
  });

  // Real handle, straight from `profiles.username` (same field the admin
  // Profiles/Users table's HANDLE column reads — see AdminUserRow/_UserRow
  // in settings_tab.dart) — NOT derived from the email address. A guest
  // session carries no username (and no real identity behind it at all),
  // so it keeps the fixed '@guest' label; a real account with no username
  // set yet returns null so the caller hides the handle entirely instead
  // of falling back to something misleading like the email prefix.
  String? get _handle {
    if (user.isGuest) return '@guest';
    final username = user.username;
    if (username == null || username.isEmpty) return null;
    return '@$username';
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
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: _kInk,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          // Role identity pill — shows the account's real
                          // `profiles.role` (via Role.label), not a static
                          // "Member" string. Color comes from
                          // Role.badgeColor (models/role.dart), the same
                          // shared config the admin Profiles/Users table's
                          // ROLE column uses (settings_tab.dart's
                          // _UserRow), so the two surfaces can't disagree
                          // on a role's color or label. Admin-tier roles
                          // (Role.isAdminTier) get a bolder/bordered
                          // treatment so Super Admin/Admin genuinely stand
                          // out; Guide/Traveller stay in the original
                          // subtle low-alpha pill. Guest keeps its own
                          // fixed neutral-gray "Guest" label — a guest
                          // session's `role` is just the unset default, not
                          // a real earned tier.
                          Builder(builder: (context) {
                            final prominent =
                                !user.isGuest && user.role.isAdminTier;
                            final color =
                                user.isGuest ? _kMute : user.role.badgeColor;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(
                                    alpha: prominent ? 0.22 : 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: prominent
                                    ? Border.all(
                                        color: color.withValues(alpha: 0.55))
                                    : null,
                              ),
                              child: Text(
                                  user.isGuest ? 'Guest' : user.role.label,
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: prominent
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: color)),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Handle + member-since collapsed onto a single gray
                      // subtext line (was two stacked lines) — e.g.
                      // "@sahil.adlakha.vn · Member since Jun 2026".
                      Text(
                        [
                          if (_handle != null) _handle!,
                          if (memberSince != null) memberSince!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: _kMute,
                        ),
                      ),
                    ],
                  ),
                ),
                if (stats != null) ...[
                  const SizedBox(width: 12),
                  stats!,
                ],
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
              color: _kCard.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder),
            ),
            child: Icon(icon, size: 18, color: iconColor ?? _kInk),
          ),
        ),
      ),
    );
  }
}

/// Flat, solid mint-teal rounded square — replaces the old photo/illustrated
/// avatar (network image when [AuthUser.avatarUrl] was set, a gradient
/// circle otherwise) per the dark-redesign reference, which shows no photo
/// treatment at all, just a flat identity square + the online dot. This is a
/// deliberate behavior change: a real OAuth profile photo (when present)
/// no longer renders here — flagged since it's a visible functionality
/// change, not just a color swap.
class _Avatar extends StatelessWidget {
  final AuthUser user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kTeal,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(color: _kPage, width: 2.5),
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
  /// trip at all — a genuinely different state from "zero alerts on an active
  /// trip" (which already renders a plain "0" below). Both null and zero are
  /// rendered as "0" here per the redesign's call for one consistent
  /// empty-state digit across every cell — the underlying null-vs-zero
  /// distinction is real, but a bare em-dash next to three all-numeric
  /// siblings read as broken formatting rather than a meaningful signal, and
  /// nothing else on this bar explains what a dash would mean.
  final int gems, trips;
  final int? alerts;
  final double spent;
  final bool loading;
  // False (default): the original full-width row, one Expanded cell each,
  // stacked below the header — unchanged mobile shape. True: shrink-wrapped
  // horizontal chips (icon + value, no label, no vertical padding) sized to
  // sit inline next to the name/handle in _Header's row on desktop (item 7
  // of the 2026-09-18 redesign) — that row has nowhere near this bar's
  // native ~600px width to give each cell, so the compact form drops the
  // label text and stacked layout rather than squeezing the full cell into
  // a fraction of its size.
  final bool compact;
  const _StatsBar({
    required this.gems,
    required this.trips,
    required this.alerts,
    required this.spent,
    required this.loading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final alertCount = alerts ?? 0;
    final hasAlerts = alertCount > 0;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactCell(Icons.card_travel_outlined, '$trips', _kInk),
          _compactCell(Icons.bookmark_border, '$gems', _kInk),
          _compactCell(Icons.receipt_long_outlined,
              loading ? '··' : '\$${spent.toStringAsFixed(0)}', _kInk),
          _compactCell(Icons.notifications_none_rounded, '$alertCount',
              hasAlerts ? _kWarn : _kInk, last: true),
        ],
      );
    }
    // No glass card / border box anymore — the row now blends straight into
    // the dark page background, separated only by the thin dividers between
    // cells (item 6 of the dark-redesign pass). More vertical whitespace
    // than the old boxed version, since it no longer needs to visually
    // "contain" the row.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Row(
        children: [
          _cell(Icons.card_travel_outlined, '$trips', 'Trips', _kInk),
          _divider(),
          _cell(Icons.bookmark_border, '$gems', 'Saved', _kInk),
          _divider(),
          _cell(
              Icons.receipt_long_outlined,
              loading ? '··' : '\$${spent.toStringAsFixed(0)}',
              'Split spend',
              _kInk),
          _divider(),
          _cell(Icons.notifications_none_rounded, '$alertCount', 'Alerts',
              hasAlerts ? _kWarn : _kInk),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 34, color: _kBorder);

  // Every cell shares the same neutral ink color/weight regardless of which
  // stat it is — color is reserved for attention states (currently just
  // ALERTS turning _kWarn once count > 0), not for decorating each stat with
  // a different brand hue the way the old cells did.
  Widget _cell(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color == _kInk ? _kMute : color),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.inter(fontSize: 11.5, color: _kMute)),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1)),
          ],
        ),
      ),
    );
  }

  Widget _compactCell(IconData icon, String value, Color color,
      {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(right: last ? 0 : 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color == _kInk ? _kMute : color),
          const SizedBox(width: 5),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// TAB BAR
// ─────────────────────────────────────────
/// Plain text tab row sitting directly on the dark page background — no
/// wrapping capsule anymore (was a tan/beige `_kStripe` pill). The active
/// tab gets its own white pill with black text; inactive tabs are bare gray
/// text. Individually-animated per-tab pills (AnimatedContainer) rather
/// than one sliding highlight across a shared track, since there's no
/// shared track to slide within anymore.
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final i = e.key;
            final isActive = i == active;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    e.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? Colors.black : _kMute,
                    ),
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

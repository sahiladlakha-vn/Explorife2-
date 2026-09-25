part of '../profile_screen.dart';

// Settings tab.
//
// Desktop/web (Breakpoints.isDesktop — see _SettingsTabState.build for why
// that check, not the constraints.maxWidth/LayoutBuilder pattern
// gem_detail_screen.dart and destination_landing_screen.dart use) gets a
// sidebar-plus-panel layout: five categories as a vertical nav list, no
// full navigation on tap — just a client-side selection swap, since this
// reads as one screen with tabs, not five routes. Mobile keeps the
// original stacked drill-down list untouched (see _buildMobile).

// ─────────────────────────────────────────
// SETTINGS TAB
// ─────────────────────────────────────────

enum _SettingsCategory { editProfile, users, profiles, notifications, privacy, helpSupport }

class _SettingsTab extends StatefulWidget {
  final VoidCallback onSignOut;
  // Same value _Header already renders (see ProfileScreen.build, computed
  // once via _memberSince and threaded to both) — a heuristic (earliest
  // saved-gem/story timestamp), not a real account-creation date, and
  // `null` for any account with neither yet. The desktop Edit Profile panel
  // hides its "Member since" line entirely when this is null rather than
  // showing an empty/misleading row.
  final String? memberSince;
  const _SettingsTab({required this.onSignOut, required this.memberSince});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  _SettingsCategory _category = _SettingsCategory.editProfile;

  // UI only — no backing store yet. These are real product settings
  // (worth their own preferences table + provider eventually), but
  // standing that up was explicitly out of scope for this layout pass —
  // local widget state that's honest about not persisting beats a toggle
  // that looks like it saves and silently doesn't. Resets on reload.
  final Map<String, bool> _notifToggles = {
    'Trip reminders': true,
    'New gems nearby': true,
    'Expense split alerts': false,
  };
  final Map<String, bool> _privacyToggles = {
    'Show trips to friends': true,
    'Share location for nearby gems': false,
  };

  @override
  Widget build(BuildContext context) {
    // Breakpoints.isDesktop(context) (MediaQuery/window-width), matching
    // ProfileScreen (this tab's direct parent) — deliberately NOT the
    // LayoutBuilder/constraints.maxWidth pattern gem_detail_screen.dart and
    // destination_landing_screen.dart use to work around a persistent
    // side-nav rail. AppShell's actual tablet/desktop nav
    // (widgets/common/app_shell.dart) is two overlay panels that slide
    // over content rather than reserving a column ("neither panel reserves
    // a permanent column, both overlay" — that file's own comment), so
    // there's no rail here to make a window-width check misfire the way
    // those two screens' comments describe.
    return Breakpoints.isDesktop(context)
        ? _buildDesktop(context)
        : _buildMobile(context);
  }

  // Same predicate that already gates attraction_moderation_screen.dart /
  // restaurant_moderation_screen.dart — content moderator, regional admin,
  // super admin, or finance admin. Governs both whether the "Users"
  // sidebar item renders at all and (defensively) whether _panelFor will
  // actually hand back the Users panel, so a role change mid-session (e.g.
  // a demotion on refresh) can't leave a non-admin's panel state pointed
  // at a category their own sidebar no longer shows.
  bool _isAdmin(BuildContext context) =>
      context.watch<AuthProvider>().role.isAdminTier;

  // Narrower than _isAdmin above — gates the ROLE column's edit affordance
  // inside the Users/Profiles tables, not a sidebar item. Mirrors
  // is_super_admin() server-side (profiles_update_admin policy +
  // admin_update_user_role RPC): the full admin tier can already *see*
  // every profile via _isAdmin, but only a super_admin can actually change
  // someone's role. This is UI convenience only — the RPC re-checks the
  // caller's role itself and raises for anyone else, same defense-in-depth
  // pattern as _isAdmin's own doc comment.
  bool _isSuperAdmin(BuildContext context) =>
      context.watch<AuthProvider>().role == Role.superAdmin;

  // ── Mobile — unchanged from before this redesign. ──
  Widget _buildMobile(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _Card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _settingRow(Icons.person_outline, 'Edit profile', () async {
                // Real account required — a guest's display name/username
                // update would persist fine at the DB layer, but ProfileChrome
                // always renders '@guest' regardless (profile_chrome.dart)
                // and a guest can't be found by findUserByIdentifier anyway
                // (no email/username to match on), so there'd be nowhere
                // for the change to actually show up.
                if (!await requireAccount(context,
                    action: 'edit_profile',
                    reason: 'Sign in to set your name and username.')) {
                  return;
                }
                if (!context.mounted) return;
                showEditProfileSheet(context);
              }),
              _settingRow(Icons.notifications_outlined, 'Notifications', () {}),
              _settingRow(Icons.lock_outline, 'Privacy', () {}),
              _settingRow(Icons.receipt_long_outlined, 'Expense Splits',
                  () => context.go('/splits')),
              _settingRow(Icons.help_outline, 'Help & support', () {}),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: widget.onSignOut,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, size: 18, color: Colors.red),
                const SizedBox(width: 8),
                Text('Sign Out',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingRow(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _kInk),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _kMute),
          ],
        ),
      ),
    );
  }

  // ── Desktop — sidebar + panel. ──
  Widget _buildDesktop(BuildContext context) {
    final isAdmin = _isAdmin(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 230, child: _sidebar(context, isAdmin)),
        Expanded(
          // The Users table (and, in principle, any future panel) can be
          // taller than the viewport — ProfileScreen's own body never wraps
          // tab content in a scroll view (each tab owns its own), so
          // without this the panel silently clips at the Expanded's bottom
          // edge with no way to reach the rest of it. SingleChildScrollView
          // + Align/ConstrainedBox is the standard combination for "cap the
          // width, left-align, but let height grow and scroll": Align
          // shrink-wraps to its child on the (here, unbounded) scroll axis
          // instead of trying to expand infinitely.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 28, 24, 24),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // Users gets a wider cap than the form-shaped panels below
                // — a 6-column table (avatar/name/handle/role/joined/trips)
                // squeezed into the same 520px a two-field form uses would
                // be unreadable; a data table and a form aren't "content"
                // in the same sense, so they don't need the same cap.
                constraints: BoxConstraints(
                    maxWidth: _category == _SettingsCategory.users ||
                            _category == _SettingsCategory.profiles
                        ? 1120
                        : 520),
                child: _panelFor(_category, isAdmin),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sidebar(BuildContext context, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _navItem(Icons.person_outline, 'Edit profile',
              _SettingsCategory.editProfile),
          // Admin-only — see _isAdmin's doc comment. Hiding this is a
          // convenience for everyone else, not the access control: the
          // panel's own query (admin_list_users, a SECURITY DEFINER
          // Postgres function) re-checks the caller's role server-side and
          // returns nothing for a non-admin regardless of what the client
          // renders. The "Admin" tag marks it as a different kind of
          // settings item than the other four, not a personal preference.
          if (isAdmin)
            _navItem(Icons.admin_panel_settings_outlined, 'Users',
                _SettingsCategory.users,
                tag: 'Admin'),
          // Same admin gate as Users. A Salesforce-style "Setup → Profiles"
          // catalog: one row per [Role] (Permission set + description +
          // member count), not per account — see _ProfilesPanel. The old
          // "every profiles row including guest sessions" dump that used to
          // live here moved under Users as its "All accounts" toggle
          // instead, so no existing visibility was lost.
          if (isAdmin)
            _navItem(Icons.groups_outlined, 'Profiles',
                _SettingsCategory.profiles,
                tag: 'Admin'),
          _navItem(Icons.notifications_outlined, 'Notifications',
              _SettingsCategory.notifications),
          _navItem(Icons.lock_outline, 'Privacy', _SettingsCategory.privacy),
          // Expense Splits stays a real route (SplitsScreen/
          // SplitDetailScreen — live CRUD against SplitsProvider, shared
          // with the Overview tab's stats) rather than inline panel
          // content — a data-bound list-plus-detail feature doesn't belong
          // folded into a settings side panel just for layout consistency.
          // The trailing chevron (vs. the plain nav items above) signals
          // that this one navigates away instead of swapping the panel.
          _linkItem(Icons.receipt_long_outlined, 'Expense Splits',
              () => context.go('/splits')),
          _navItem(Icons.help_outline, 'Help & support',
              _SettingsCategory.helpSupport),
          const SizedBox(height: 12),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 12),
          // Plain destructive-red text — not the full-width red-tinted bar
          // mobile still uses (see _buildMobile). That heavier treatment is
          // reserved for a genuinely rare/severe action (e.g. delete
          // account, if this app ever grows one); routine sign-out doesn't
          // need to shout.
          GestureDetector(
            onTap: widget.onSignOut,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.logout, size: 18, color: _kCritical),
                  const SizedBox(width: 12),
                  Text('Sign out',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _kCritical)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, _SettingsCategory value,
      {String? tag}) {
    final active = _category == value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: () => setState(() => _category = value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            // Same white-fill/black-text "active" treatment _TabBar already
            // uses on this dark profile surface (profile_chrome.dart) —
            // reused rather than inventing a second "selected" style.
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? Colors.black : _kInk),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? Colors.black : _kInk)),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.black.withValues(alpha: 0.08)
                        : AppTheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tag,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.black : AppTheme.primary)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkItem(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _kInk),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _kInk)),
              ),
              const Icon(Icons.chevron_right, size: 16, color: _kMute),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelFor(_SettingsCategory category, bool isAdmin) {
    switch (category) {
      case _SettingsCategory.editProfile:
        return _EditProfilePanel(memberSince: widget.memberSince);
      case _SettingsCategory.users:
        // Defensive fallback, not the real access control (that's the
        // admin_list_users function server-side) — covers the edge case
        // of _category already being `users` when isAdmin flips to false
        // (e.g. a role change lands mid-session), so the panel doesn't
        // sit on a sidebar item that just disappeared.
        return isAdmin ? const _UsersPanel() : _EditProfilePanel(memberSince: widget.memberSince);
      case _SettingsCategory.profiles:
        // Same defensive fallback as Users, above. This used to be the
        // same raw/anonymous-inclusive _UsersPanel as Users with different
        // copy — that view now lives inside Users itself as its "All
        // accounts" toggle (see _UsersPanelState._includeAnonymous). This
        // is the real Salesforce-style Profiles catalog: one row per
        // [Role], not per account.
        return isAdmin
            ? const _ProfilesPanel()
            : _EditProfilePanel(memberSince: widget.memberSince);
      case _SettingsCategory.notifications:
        return _TogglePanel(
          title: 'Notifications',
          subtitle: 'Choose what you want to hear about.',
          toggles: _notifToggles,
          onChanged: (key, value) =>
              setState(() => _notifToggles[key] = value),
        );
      case _SettingsCategory.privacy:
        return _TogglePanel(
          title: 'Privacy',
          subtitle: 'Control what other travelers can see.',
          toggles: _privacyToggles,
          onChanged: (key, value) =>
              setState(() => _privacyToggles[key] = value),
        );
      case _SettingsCategory.helpSupport:
        return const _HelpSupportPanel();
    }
  }
}

/// Desktop Edit Profile panel — same two real, editable AuthUser fields as
/// the mobile EditProfileSheet (display name, username), saved through the
/// exact same [saveProfileEdit] helper so the two surfaces can't drift on
/// validation or error handling. Adds two read-only elements the mobile
/// sheet doesn't have: the avatar and "Member since".
class _EditProfilePanel extends StatefulWidget {
  final String? memberSince;
  const _EditProfilePanel({required this.memberSince});

  @override
  State<_EditProfilePanel> createState() => _EditProfilePanelState();
}

class _EditProfilePanelState extends State<_EditProfilePanel> {
  late final _nameCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.name ?? '');
  late final _usernameCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.username ?? '');
  bool _saving = false;
  String? _error;
  bool _justSaved = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _justSaved = false;
    });
    final error = await saveProfileEdit(context,
        name: _nameCtrl.text, username: _usernameCtrl.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      _justSaved = error == null;
    });
  }

  InputDecoration _fieldDecoration() => InputDecoration(
        filled: true,
        fillColor: _kPage,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      );

  TextStyle get _labelStyle => GoogleFonts.inter(
      fontSize: 12.5, fontWeight: FontWeight.w600, color: _kMute);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Edit profile',
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
        const SizedBox(height: 20),
        // Read-only — no photo-upload flow exists anywhere in the app yet
        // (no picker, no storage write, no updateAvatarUrl call). Wiring
        // that up is a real feature, not a layout change, so it's
        // deliberately deferred rather than shipping a "Change photo"
        // button that looks functional and isn't. Flat teal square, not
        // the real OAuth avatarUrl — matches profile_chrome.dart's own
        // _Avatar treatment on this same profile surface, which stopped
        // rendering real photos deliberately (see that class's doc
        // comment); this stays consistent with it instead of
        // reintroducing photo rendering in just this one spot.
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              color: _kTeal, borderRadius: BorderRadius.circular(18)),
        ),
        const SizedBox(height: 24),
        Text('Display name', style: _labelStyle),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          style: GoogleFonts.inter(fontSize: 14, color: _kInk),
          decoration: _fieldDecoration(),
        ),
        const SizedBox(height: 18),
        Text('Username', style: _labelStyle),
        const SizedBox(height: 6),
        TextField(
          controller: _usernameCtrl,
          style: GoogleFonts.inter(fontSize: 14, color: _kInk),
          decoration: _fieldDecoration(),
        ),
        const SizedBox(height: 6),
        Text('This is how other travelers find you when they add you to a trip.',
            style: GoogleFonts.inter(fontSize: 11.5, color: _kMute)),
        // Heuristic, not a real account-creation date (see _SettingsTab's
        // doc comment on `memberSince`) — hidden entirely rather than
        // shown blank/misleading when there's nothing to derive it from
        // yet.
        if (widget.memberSince != null) ...[
          const SizedBox(height: 20),
          Text(widget.memberSince!,
              style: GoogleFonts.inter(
                  fontSize: 13.5, fontWeight: FontWeight.w500, color: _kMute)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!,
              style: GoogleFonts.inter(fontSize: 12.5, color: _kCritical)),
        ],
        if (_justSaved) ...[
          const SizedBox(height: 14),
          Text('Saved.',
              style: GoogleFonts.inter(fontSize: 12.5, color: _kGreen)),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('Save changes',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

/// Shared shape for Notifications/Privacy — see _SettingsTabState's
/// `_notifToggles`/`_privacyToggles` doc comment: presentation-only, no
/// backing preferences store yet.
class _TogglePanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, bool> toggles;
  final void Function(String key, bool value) onChanged;
  const _TogglePanel({
    required this.title,
    required this.subtitle,
    required this.toggles,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
        const SizedBox(height: 20),
        for (final entry in toggles.entries) ...[
          Row(
            children: [
              Expanded(
                child: Text(entry.key,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _kInk)),
              ),
              Switch(
                value: entry.value,
                onChanged: (v) => onChanged(entry.key, v),
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
          const Divider(color: _kBorder, height: 1),
        ],
      ],
    );
  }
}

/// No real support channel exists anywhere in this app today — checked for
/// a help-desk tool, a general inbox, a community link, anything (none
/// found). This is an honest "not built yet" placeholder, not a stand-in
/// contact address; swap in a real channel once one exists rather than
/// inventing one here.
class _HelpSupportPanel extends StatelessWidget {
  const _HelpSupportPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Help & support',
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
        const SizedBox(height: 12),
        Text("We're building this out — check back soon.",
            style: GoogleFonts.inter(fontSize: 14, color: _kMute)),
      ],
    );
  }
}

/// Admin-only roster — see [_SettingsTabState._isAdmin]'s doc comment for
/// why reaching this panel at all already implies an admin-tier role, and
/// [AdminUserRepository]'s doc comment for why the actual access control
/// lives server-side (the `admin_list_users` function), not here.
///
/// Read-only by default (no row-level "..." overflow menu) — what an admin
/// should be able to *do* to another account beyond viewing is a separate
/// scope/risk decision, still undecided in general. The one deliberate
/// exception is [allowReassign]: the Profiles detail page (_ProfileDetailPanel)
/// passes it true for its "Assigned Users" section specifically, since
/// reassigning a user's profile from that page was an explicit, scoped
/// requirement — everywhere else this stays read-only.
class _UsersPanel extends StatefulWidget {
  // Set by _ProfileDetailPanel to scope the roster to one profile/role;
  // null (the default, plain "Users" sidebar item) matches every role.
  final Role? role;
  // Whether to show the Real accounts/All accounts segmented toggle — on
  // for the plain Users sidebar item (this is where the old, separate
  // "Profiles" raw dump moved to), off when embedded read-only inside a
  // Profile detail page (a role-scoped roster has no "guest sessions"
  // reading to toggle in the first place; every guest defaults to the
  // traveler role but isn't meaningfully "assigned" to it).
  final bool showAllAccountsToggle;
  final bool showAdminTag;
  final bool allowReassign;
  final String title;
  final String subtitle;
  const _UsersPanel({
    this.role,
    this.showAllAccountsToggle = true,
    this.showAdminTag = true,
    this.allowReassign = false,
    this.title = 'Users',
    this.subtitle = 'Every account on the platform. Read-only for now — '
        'no row actions yet.',
  });

  @override
  State<_UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<_UsersPanel> {
  static const _pageSize = 20;

  final _repo = AdminUserRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  int _page = 0;
  bool _loading = true;
  String? _error;
  AdminUserPage _result = AdminUserPage.empty;
  // Only ever flips away from false when widget.showAllAccountsToggle is
  // true (the plain Users panel) — see the toggle row in build().
  bool _includeAnonymous = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.fetchUsers(
          search: _searchCtrl.text,
          page: _page,
          pageSize: _pageSize,
          includeAnonymous: _includeAnonymous,
          role: widget.role);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A non-admin never legitimately reaches this panel (see the
        // sidebar gate + _panelFor's fallback), so a real error here means
        // an actual failure (network, RPC signature drift), not a
        // disguised permission denial — the RPC itself returns an empty
        // *result*, not an exception, for a non-admin caller.
        _error = 'Could not load users: $e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 0;
      _load();
    });
  }

  void _changePage(int delta) {
    setState(() => _page += delta);
    _load();
  }

  void _setIncludeAnonymous(bool value) {
    if (value == _includeAnonymous) return;
    setState(() {
      _includeAnonymous = value;
      _page = 0;
    });
    _load();
  }

  // Reassignment itself is enforced entirely server-side (the
  // admin_update_user_role RPC re-checks is_super_admin(), rejects an
  // anonymous target, and rejects demoting the last remaining super_admin
  // — see AdminUserRepository.updateRole's doc comment). This just calls
  // it, surfaces whatever it raises, and refreshes the roster on success
  // so a user whose role no longer matches widget.role drops out of a
  // role-scoped list immediately.
  Future<void> _reassign(AdminUserRow user, Role newRole) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.updateRole(userId: user.id, newRole: newRole);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${user.displayName ?? 'User'} reassigned to ${newRole.label}.')));
      _load();
    } on AdminRoleUpdateException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: _kCritical));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not reassign: $e'),
          backgroundColor: _kCritical));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _result.total;
    final totalPages = total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
    final isSuperAdmin = context.watch<AuthProvider>().role == Role.superAdmin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title,
                style: GoogleFonts.inter(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
            if (widget.showAdminTag) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Admin',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(widget.subtitle,
            style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
        const SizedBox(height: 16),
        if (widget.showAllAccountsToggle) ...[
          _AccountsScopeToggle(
            includeAnonymous: _includeAnonymous,
            onChanged: _setIncludeAnonymous,
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(fontSize: 14, color: _kInk),
          decoration: InputDecoration(
            hintText: 'Search by name or username',
            hintStyle: GoogleFonts.inter(fontSize: 14, color: _kMute),
            prefixIcon: const Icon(Icons.search, size: 20, color: _kMute),
            filled: true,
            fillColor: _kPage,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(_error!,
                style: GoogleFonts.inter(fontSize: 13, color: _kCritical)),
          )
        else if (_result.users.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No users found.',
                style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
          )
        else
          _UsersTable(
            users: _result.users,
            allowReassign: widget.allowReassign && isSuperAdmin,
            onReassign: _reassign,
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('$total user${total == 1 ? '' : 's'}',
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
            const Spacer(),
            IconButton(
              onPressed: _page > 0 ? () => _changePage(-1) : null,
              icon: const Icon(Icons.chevron_left, size: 20),
              color: _kInk,
              disabledColor: _kMute.withValues(alpha: 0.35),
            ),
            Text('Page ${_page + 1} of $totalPages',
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
            IconButton(
              onPressed: (_page + 1) < totalPages ? () => _changePage(1) : null,
              icon: const Icon(Icons.chevron_right, size: 20),
              color: _kInk,
              disabledColor: _kMute.withValues(alpha: 0.35),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Real accounts" / "All accounts" segmented toggle — replaces the old
/// separate "Profiles" sidebar item's includeAnonymous:true dump. Real
/// accounts (the curated, non-guest view) stays the default so nothing
/// about Users' existing behavior changes for anyone who doesn't touch
/// this control.
class _AccountsScopeToggle extends StatelessWidget {
  final bool includeAnonymous;
  final ValueChanged<bool> onChanged;
  const _AccountsScopeToggle(
      {required this.includeAnonymous, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool value) {
      final active = includeAnonymous == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.black : _kMute)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kPage,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('Real accounts', false),
          segment('All accounts', true),
        ],
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  final List<AdminUserRow> users;
  // See _UsersPanel's doc comment on [allowReassign] — only the Profile
  // detail page's Assigned Users section (and only for a super_admin caller)
  // ever passes true. [onReassign] is required together with it so a
  // caller can't turn on the affordance without wiring up what it does.
  final bool allowReassign;
  final void Function(AdminUserRow user, Role newRole)? onReassign;
  const _UsersTable({
    required this.users,
    this.allowReassign = false,
    this.onReassign,
  });

  static final _dateFormat = DateFormat('MMM d, yyyy');

  TextStyle get _headerStyle => GoogleFonts.inter(
      fontSize: 11.5, fontWeight: FontWeight.w700, color: _kMute);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 36),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: Text('NAME', style: _headerStyle)),
              Expanded(flex: 2, child: Text('HANDLE', style: _headerStyle)),
              Expanded(flex: 3, child: Text('EMAIL', style: _headerStyle)),
              SizedBox(
                  width: 128,
                  child: Text('ROLE', style: _headerStyle)),
              SizedBox(
                  width: 84,
                  child: Text('AUTH', style: _headerStyle)),
              SizedBox(
                  width: 92,
                  child: Text('JOINED', style: _headerStyle)),
              SizedBox(
                  width: 50,
                  child: Text('TRIPS',
                      textAlign: TextAlign.right, style: _headerStyle)),
              if (allowReassign) const SizedBox(width: 40),
            ],
          ),
        ),
        const Divider(color: _kBorder, height: 1),
        for (final user in users)
          _UserRow(
            user: user,
            dateFormat: _dateFormat,
            allowReassign: allowReassign,
            onReassign: onReassign == null ? null : (r) => onReassign!(user, r),
          ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUserRow user;
  final DateFormat dateFormat;
  final bool allowReassign;
  final void Function(Role newRole)? onReassign;
  const _UserRow({
    required this.user,
    required this.dateFormat,
    this.allowReassign = false,
    this.onReassign,
  });

  // auth.users.raw_app_meta_data->>'provider' as returned by admin_list_users
  // — plain lowercase provider slugs (Supabase's own vocabulary), not a
  // user-facing label. Only maps the two OAuth providers auth_provider.dart
  // actually wires up (Google, GitHub) rather than guessing at providers
  // this app doesn't offer. An anonymous row has a null provider (Supabase
  // never sets one for guest sessions) — checked first via `isAnonymous`
  // so it reads "Guest" instead of a bare, unexplained "—" now that the
  // Profiles panel surfaces these rows too (Users still excludes them).
  static String _providerLabel(String? provider, {required bool isAnonymous}) {
    if (isAnonymous) return 'Guest';
    switch (provider) {
      case 'google':
        return 'Google';
      case 'github':
        return 'GitHub';
      case null:
        return '—';
      default:
        // Anything else (e.g. a provider added to auth_provider.dart later
        // without this switch being updated) — show the raw slug rather
        // than silently mislabeling it.
        return provider;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (user.displayName == null || user.displayName!.isEmpty)
        ? 'Traveler'
        : user.displayName!;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          // Same "no raw photo" convention as _Avatar/_EditProfilePanel on
          // this profile surface, but with the initial overlaid — unlike a
          // single profile header, a roster of many rows needs some way to
          // tell users apart at a glance, and a dozen identical blank
          // squares in a column would defeat the point of an avatar
          // column entirely.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _kTeal, borderRadius: BorderRadius.circular(9)),
            child: Text(initial,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: _kInk)),
          ),
          Expanded(
            flex: 2,
            child: Text(
                user.username == null ? '—' : '@${user.username}',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
          ),
          Expanded(
            flex: 3,
            child: Text(user.email ?? '—',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
          ),
          SizedBox(
            width: 128,
            child: Align(
              alignment: Alignment.centerLeft,
              // Same Role.badgeColor/isAdminTier config the profile
              // header's identity pill uses (profile_chrome.dart's
              // _Header) — one shared source of truth for role color, so
              // this table and the header can't drift apart on which
              // roles "stand out".
              child: Builder(builder: (context) {
                final prominent = user.role.isAdminTier;
                final color = user.role.badgeColor;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: prominent ? 0.20 : 0.12),
                    border: Border.all(
                        color: color.withValues(alpha: prominent ? 0.6 : 0.35)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(user.role.label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight:
                              prominent ? FontWeight.w700 : FontWeight.w600,
                          color: color)),
                );
              }),
            ),
          ),
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  _providerLabel(user.provider,
                      isAnonymous: user.isAnonymous),
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(dateFormat.format(user.createdAt),
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
          ),
          SizedBox(
            width: 50,
            child: Text('${user.tripCount}',
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kInk)),
          ),
          // Guests/anonymous rows never reach a role-scoped roster in the
          // first place (admin_update_user_role rejects reassigning one
          // server-side anyway — see AdminUserRepository.updateRole's doc
          // comment), but hiding the affordance here too avoids offering an
          // action that would just come back as an error toast.
          if (allowReassign && !user.isAnonymous)
            SizedBox(
              width: 40,
              child: IconButton(
                onPressed: () => _showReassignDialog(context),
                icon: const Icon(Icons.edit_outlined, size: 17),
                color: _kMute,
                tooltip: 'Reassign profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            )
          else if (allowReassign)
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Future<void> _showReassignDialog(BuildContext context) async {
    Role selected = user.role;
    final displayName =
        (user.displayName == null || user.displayName!.isEmpty)
            ? 'this user'
            : user.displayName!;
    final newRole = await showDialog<Role>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: _kCard,
          title: Text('Reassign profile',
              style: GoogleFonts.inter(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _kInk)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose a new profile for $displayName.',
                    style: GoogleFonts.inter(fontSize: 13.5, color: _kMute)),
                const SizedBox(height: 16),
                DropdownButtonFormField<Role>(
                  initialValue: selected,
                  isExpanded: true,
                  dropdownColor: _kCard,
                  style: GoogleFonts.inter(fontSize: 14, color: _kInk),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _kPage,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                  items: [
                    for (final role in Role.byPrivilege)
                      DropdownMenuItem(value: role, child: Text(role.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selected = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel',
                  style: GoogleFonts.inter(fontSize: 13.5, color: _kMute)),
            ),
            ElevatedButton(
              onPressed: selected == user.role
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text('Reassign',
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (newRole == null || !context.mounted) return;
    // Second, explicit confirmation step — the dropdown pick above is just
    // choosing a value, this is the actual "yes, do it" per the spec's
    // requirement that reassignment go through a confirmation step.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Confirm reassignment',
            style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kInk)),
        content: Text(
            'Reassign $displayName from ${user.role.label} to ${newRole.label}?',
            style: GoogleFonts.inter(fontSize: 13.5, color: _kMute)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontSize: 13.5, color: _kMute)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(confirmContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: _kCritical),
            child: Text('Confirm',
                style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) onReassign?.call(newRole);
  }
}

/// Salesforce "Setup → Profiles" catalog — one row per [Role] (all 7,
/// including roles with 0 members today), NOT one row per account (that's
/// Users). Columns are Name/Description/Users/Type per the approved spec;
/// deliberately no "Last Modified" column (nothing in this app tracks when
/// a role's permission set last changed — inventing a value would be
/// worse than omitting the column) and no "New Profile" button (there's no
/// data-driven custom-profile mechanism yet — see Role.profileType's doc
/// comment; adding one is an explicitly separate, larger project).
class _ProfilesPanel extends StatefulWidget {
  const _ProfilesPanel();

  @override
  State<_ProfilesPanel> createState() => _ProfilesPanelState();
}

class _ProfilesPanelState extends State<_ProfilesPanel> {
  final _repo = AdminUserRepository();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  Map<Role, int> _counts = const {};
  // Which profile's detail page is open, if any — a client-side selection
  // swap within this same panel (matching _SettingsTabState's own
  // category-swap pattern), not a real route; there's no deep-linkable URL
  // for a single profile today.
  Role? _selectedRole;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final counts = await _repo.fetchRoleCounts();
      if (!mounted) return;
      setState(() {
        _counts = {for (final c in counts) c.role: c.userCount};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load profiles: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRole;
    if (selected != null) {
      return _ProfileDetailPanel(
        role: selected,
        userCount: _counts[selected] ?? 0,
        onBack: () => setState(() => _selectedRole = null),
      );
    }

    final query = _searchCtrl.text.trim().toLowerCase();
    final roles = Role.byPrivilege.where((role) {
      if (query.isEmpty) return true;
      return role.label.toLowerCase().contains(query) ||
          role.description.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Profiles',
                style: GoogleFonts.inter(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Admin',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
            'Permission sets every account on the platform is assigned one of.',
            style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
        const SizedBox(height: 16),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 14, color: _kInk),
          decoration: InputDecoration(
            hintText: 'Search profiles',
            hintStyle: GoogleFonts.inter(fontSize: 14, color: _kMute),
            prefixIcon: const Icon(Icons.search, size: 20, color: _kMute),
            filled: true,
            fillColor: _kPage,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(_error!,
                style: GoogleFonts.inter(fontSize: 13, color: _kCritical)),
          )
        else if (roles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No profiles match "$query".',
                style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
          )
        else
          _ProfilesTable(
            roles: roles,
            counts: _counts,
            onTap: (role) => setState(() => _selectedRole = role),
          ),
      ],
    );
  }
}

class _ProfilesTable extends StatelessWidget {
  final List<Role> roles;
  final Map<Role, int> counts;
  final ValueChanged<Role> onTap;
  const _ProfilesTable(
      {required this.roles, required this.counts, required this.onTap});

  TextStyle get _headerStyle => GoogleFonts.inter(
      fontSize: 11.5, fontWeight: FontWeight.w700, color: _kMute);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('NAME', style: _headerStyle)),
              Expanded(flex: 5, child: Text('DESCRIPTION', style: _headerStyle)),
              SizedBox(
                  width: 70,
                  child: Text('USERS',
                      textAlign: TextAlign.right, style: _headerStyle)),
              SizedBox(
                  width: 90,
                  child: Text('TYPE',
                      textAlign: TextAlign.right, style: _headerStyle)),
            ],
          ),
        ),
        const Divider(color: _kBorder, height: 1),
        for (final role in roles)
          _ProfileRow(
            role: role,
            userCount: counts[role] ?? 0,
            onTap: () => onTap(role),
          ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final Role role;
  final int userCount;
  final VoidCallback onTap;
  const _ProfileRow(
      {required this.role, required this.userCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = role.badgeColor;
    final prominent = role.isAdminTier;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: prominent ? 0.20 : 0.12),
                      border: Border.all(
                          color:
                              color.withValues(alpha: prominent ? 0.6 : 0.35)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(role.label,
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight:
                                prominent ? FontWeight.w700 : FontWeight.w600,
                            color: color)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(role.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text('$userCount',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _kInk)),
            ),
            SizedBox(
              width: 90,
              child: Text(role.profileType.label,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One profile's detail page — header, Permissions (grouped by
/// [PermissionDisplay.area], strictly [permissionsFor] the role, nothing
/// invented), and Assigned Users (the same [_UsersPanel] Users itself uses,
/// scoped to this role via its `role` param). Only a super_admin caller
/// gets the reassign affordance inside that embedded table — see
/// [_UsersPanel]'s doc comment; a Content Moderator or Regional Admin can
/// still open this page (both are admin-tier) but can only look, matching
/// [hasPermission]'s [Permission.assignChangeUserRoles] cell (super_admin
/// only).
class _ProfileDetailPanel extends StatelessWidget {
  final Role role;
  final int userCount;
  final VoidCallback onBack;
  const _ProfileDetailPanel(
      {required this.role, required this.userCount, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final granted = permissionsFor(role);
    final byArea = <String, List<GrantedPermission>>{};
    for (final g in granted) {
      byArea.putIfAbsent(g.permission.area, () => []).add(g);
    }
    final color = role.badgeColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onBack,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back, size: 16, color: _kMute),
              const SizedBox(width: 6),
              Text('All profiles',
                  style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: role.isAdminTier ? 0.20 : 0.12),
                border: Border.all(
                    color: color
                        .withValues(alpha: role.isAdminTier ? 0.6 : 0.35)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(role.label,
                  style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ),
            const SizedBox(width: 10),
            Text(role.profileType.label,
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
          ],
        ),
        const SizedBox(height: 10),
        Text(role.description,
            style: GoogleFonts.inter(
                fontSize: 13.5, color: _kMute, height: 1.4)),
        const SizedBox(height: 8),
        Text('$userCount user${userCount == 1 ? '' : 's'} assigned',
            style: GoogleFonts.inter(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: _kInk)),
        const SizedBox(height: 28),
        Text('Permissions',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: _kInk)),
        const SizedBox(height: 4),
        Text('What this profile is actually granted — nothing more.',
            style: GoogleFonts.inter(fontSize: 12.5, color: _kMute)),
        const SizedBox(height: 14),
        if (granted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('This profile has no granted permissions.',
                style: GoogleFonts.inter(fontSize: 13, color: _kMute)),
          )
        else
          for (final area in byArea.keys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(area,
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kMute,
                      letterSpacing: 0.3)),
            ),
            for (final g in byArea[area]!)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 15, color: _kGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(g.permission.label,
                          style: GoogleFonts.inter(
                              fontSize: 13.5, color: _kInk)),
                    ),
                    if (g.ownOnly)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kWarn.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Own only',
                            style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: _kWarn)),
                      ),
                  ],
                ),
              ),
          ],
        const SizedBox(height: 28),
        _UsersPanel(
          role: role,
          showAllAccountsToggle: false,
          showAdminTag: false,
          allowReassign: true,
          title: 'Assigned Users',
          subtitle:
              'Every real account currently assigned the ${role.label} profile.',
        ),
      ],
    );
  }
}

part of '../profile_screen.dart';

// Settings tab.

// ─────────────────────────────────────────
// SETTINGS TAB
// ─────────────────────────────────────────
class _SettingsTab extends StatelessWidget {
  final VoidCallback onSignOut;
  const _SettingsTab({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
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
          onTap: onSignOut,
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
                    style: GoogleFonts.fredoka(
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
                  style: GoogleFonts.fredoka(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _kMute),
          ],
        ),
      ),
    );
  }
}



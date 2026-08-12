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
              _settingRow(Icons.person_outline, 'Edit profile',
                  () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _EditProfileSheet(),
                      )),
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
                    style: GoogleFonts.dmSans(
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
                  style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _kMute),
          ],
        ),
      ),
    );
  }
}

/// Display name + username editor. Same shape as _AddDocumentSheet/
/// _AddPackingItemSheet (DraggableScrollableSheet, _lightFieldDecoration) —
/// the first "edit yourself" sheet in the app, since this settings row was
/// previously a dead stub.
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _nameCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.name ?? '');
  late final _usernameCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.username ?? '');
  static final _usernameFormat = RegExp(r'^[a-z0-9_]{3,20}$');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isNotEmpty && !_usernameFormat.hasMatch(username)) {
      setState(() =>
          _error = 'Usernames are 3–20 lowercase letters, numbers, or underscores.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      if (name.isNotEmpty) await auth.updateDisplayName(name);
      if (username != (auth.user?.username ?? '')) {
        await auth.updateUsername(username);
      }
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      setState(() {
        _saving = false;
        _error = e.code == '23505'
            ? 'That username is already taken.'
            : e.code == '23514'
                ? 'Usernames are 3–20 lowercase letters, numbers, or underscores.'
                : 'Could not save: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _kPage,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: _kBorder, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit profile',
                        style:
                            GoogleFonts.bebasNeue(fontSize: 18, color: _kInk)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      style: GoogleFonts.dmSans(fontSize: 14, color: _kInk),
                      decoration: _lightFieldDecoration('Display name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameCtrl,
                      style: GoogleFonts.dmSans(fontSize: 14, color: _kInk),
                      decoration:
                          _lightFieldDecoration('Username (e.g. sahil_j)'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        "This is how other travelers find you when they add you to a trip.",
                        style: GoogleFonts.dmSans(fontSize: 11.5, color: _kMute)),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: GoogleFonts.dmSans(
                              fontSize: 12.5, color: _kCritical)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Save',
                              style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


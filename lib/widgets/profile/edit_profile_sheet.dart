import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Display name + username editor — the one "edit yourself" sheet in the
/// app, shared between the Settings tab's "Edit profile" row and the
/// desktop/tablet profile panel's signed-in state (ProfilePanel). Extracted
/// out of profile_screen.dart's part-file family (it used to be private
/// there) so a widget tree outside that family — AppShell's ProfilePanel —
/// can open the exact same sheet instead of a second copy.
class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
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
      setState(() => _error =
          'Usernames are 3–20 lowercase letters, numbers, or underscores.');
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

  static InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.fredoka(fontSize: 14, color: AppTheme.lightMute),
        filled: true,
        fillColor: AppTheme.lightCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.lightSurface,
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
                      color: AppTheme.lightBorder,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit profile',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 18, color: AppTheme.lightInk)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      style:
                          GoogleFonts.fredoka(fontSize: 14, color: AppTheme.lightInk),
                      decoration: _fieldDecoration('Display name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameCtrl,
                      style:
                          GoogleFonts.fredoka(fontSize: 14, color: AppTheme.lightInk),
                      decoration: _fieldDecoration('Username (e.g. sahil_j)'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        "This is how other travelers find you when they add you to a trip.",
                        style: GoogleFonts.fredoka(
                            fontSize: 11.5, color: AppTheme.lightMute)),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: GoogleFonts.fredoka(
                              fontSize: 12.5, color: const Color(0xFFD32F2F))),
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
                              style: GoogleFonts.fredoka(
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

/// Opens [EditProfileSheet] the same way everywhere it's triggered from
/// (Settings tab's row, ProfilePanel's "Edit Profile" link) — one call site
/// for the modal-sheet boilerplate instead of repeating it per caller.
Future<void> showEditProfileSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const EditProfileSheet(),
  );
}

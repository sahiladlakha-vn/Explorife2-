import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/hike_provider.dart';

class LogHikeScreen extends StatefulWidget {
  const LogHikeScreen({super.key});
  @override
  State<LogHikeScreen> createState() => _LogHikeScreenState();
}

class _LogHikeScreenState extends State<LogHikeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _distCtrl = TextEditingController();
  final _eleCtrl = TextEditingController();
  int _hours = 0, _minutes = 0;
  String _activityType = 'hiking';
  bool _submitting = false;

  static const _activities = [
    ('hiking', '🥾', 'Hiking'),
    ('trail_running', '🏃', 'Trail Run'),
    ('cycling', '🚴', 'Cycling'),
    ('climbing', '⛰️', 'Climbing'),
    ('kayaking', '🚣', 'Kayaking'),
    ('skiing', '⛷️', 'Skiing'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _distCtrl.dispose();
    _eleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;

    setState(() => _submitting = true);
    final durationSecs = (_hours * 3600) + (_minutes * 60);
    final ok = await context.read<HikeProvider>().logHike(
      userId: auth.user!.id,
      title: _titleCtrl.text.trim(),
      activityType: _activityType,
      distanceKm: double.tryParse(_distCtrl.text),
      durationSeconds: durationSecs > 0 ? durationSecs : null,
      elevationGainM: double.tryParse(_eleCtrl.text),
    );

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hike logged! 🥾')));
        context.go('/hikes');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to log hike')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text('LOG HIKE',
            style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label('ACTIVITY TYPE'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _activities.map((a) {
                final sel = _activityType == a.$1;
                return GestureDetector(
                  onTap: () => setState(() => _activityType = a.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? AppTheme.primary : AppTheme.divider),
                    ),
                    child: Text('${a.$2}  ${a.$3}',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: sel ? Colors.white : AppTheme.textSecondary,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            _Label('TITLE *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleCtrl,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('e.g. Morning trail up Fansipan'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _Label('DISTANCE (km)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _distCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('e.g. 12.5'),
            ),
            const SizedBox(height: 16),

            _Label('DURATION'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hours', style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: _hours,
                    dropdownColor: AppTheme.surface,
                    style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
                    decoration: _deco('0'),
                    items: List.generate(24, (i) => DropdownMenuItem(
                        value: i, child: Text('$i h'))),
                    onChanged: (v) => setState(() => _hours = v ?? 0),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Minutes', style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: _minutes,
                    dropdownColor: AppTheme.surface,
                    style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
                    decoration: _deco('0'),
                    items: [0, 5, 10, 15, 20, 30, 45].map((m) =>
                        DropdownMenuItem(value: m, child: Text('$m min'))).toList(),
                    onChanged: (v) => setState(() => _minutes = v ?? 0),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),

            _Label('ELEVATION GAIN (m)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _eleCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('e.g. 450'),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Text('LOG HIKE 🥾',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 20, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppTheme.textSecondary.withOpacity(0.5)),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.jetBrainsMono(
          fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 0.8));
}

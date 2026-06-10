import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';

class SubmitStoryScreen extends StatefulWidget {
  const SubmitStoryScreen({super.key});

  @override
  State<SubmitStoryScreen> createState() => _SubmitStoryScreenState();
}

class _SubmitStoryScreenState extends State<SubmitStoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  String? _adventureType;
  String? _difficulty;
  int _lonelinessLevel = 3;
  String? _safetyLevel;
  String? _connectivity;
  String? _aftermath;
  bool _submitting = false;

  static const _difficulties = ['Easy', 'Moderate', 'Hard', 'Expert'];
  static const _safetyLevels = ['very safe', 'comfortable', 'risky', 'dangerous'];
  static const _connectivityLevels = ['great', 'decent', 'weak', 'none'];
  static const _aftermathLevels = ['euphoric', 'grounded', 'humbled', 'shaken'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _emailCtrl.dispose();
    _locationCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final ok = await context.read<StoryProvider>().submitStory(
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      adventureType: _adventureType,
      difficulty: _difficulty,
      lonelinessLevel: _lonelinessLevel,
      safetyLevel: _safetyLevel,
      connectivity: _connectivity,
      aftermath: _aftermath,
    );

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Story Submitted! 🎉',
                style: GoogleFonts.bebasNeue(fontSize: 22, color: AppTheme.textPrimary)),
            content: Text(
              'Your story is under review. We\'ll publish it once approved.',
              style: GoogleFonts.dmSans(color: AppTheme.textSecondary, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/stories');
                },
                child: Text('OK', style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit. Try again.')),
        );
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('SUBMIT STORY',
            style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Intro blurb
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Text(
                'Share your adventure with 84,000+ explorers. All stories are reviewed before publishing.',
                style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),

            _Label('TITLE *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleCtrl,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('e.g. 7 Days Alone in the Vietnamese Highlands'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _Label('YOUR EMAIL *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('your@email.com'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _Label('ADVENTURE TYPE'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: Story.adventureTypes.map((t) {
                final sel = _adventureType == t;
                return GestureDetector(
                  onTap: () => setState(() => _adventureType = sel ? null : t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? AppTheme.primary : AppTheme.divider),
                    ),
                    child: Text(
                      '${Story.typeEmoji[t] ?? '📖'}  $t',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: sel ? Colors.white : AppTheme.textSecondary,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            _Label('LOCATION'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationCtrl,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _deco('e.g. Ha Giang Loop, Vietnam'),
            ),
            const SizedBox(height: 16),

            _Label('DIFFICULTY'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _difficulties.map((d) {
                final sel = _difficulty == d;
                return ChoiceChip(
                  label: Text(d),
                  selected: sel,
                  onSelected: (_) => setState(() => _difficulty = sel ? null : d),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: GoogleFonts.dmSans(
                      color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 13),
                  side: BorderSide(color: sel ? AppTheme.primary : AppTheme.divider),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Story content
            _Label('YOUR STORY *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contentCtrl,
              maxLines: 10,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary, height: 1.6),
              decoration: _deco('Tell your story...'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 24),

            // Reality check section
            Text('REALITY CHECK',
                style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text('Help future adventurers know what to expect',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),

            _Label('LONELINESS LEVEL: $_lonelinessLevel / 5'),
            Slider(
              value: _lonelinessLevel.toDouble(),
              min: 1, max: 5, divisions: 4,
              activeColor: AppTheme.primary,
              inactiveColor: AppTheme.surface2,
              onChanged: (v) => setState(() => _lonelinessLevel = v.round()),
            ),
            const SizedBox(height: 12),

            _Label('SAFETY'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _safetyLevels.map((v) {
                final sel = _safetyLevel == v;
                return ChoiceChip(
                  label: Text(v),
                  selected: sel,
                  onSelected: (_) => setState(() => _safetyLevel = sel ? null : v),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: GoogleFonts.dmSans(
                      color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12),
                  side: BorderSide(color: sel ? AppTheme.primary : AppTheme.divider),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            _Label('INTERNET CONNECTIVITY'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _connectivityLevels.map((v) {
                final sel = _connectivity == v;
                return ChoiceChip(
                  label: Text(v),
                  selected: sel,
                  onSelected: (_) => setState(() => _connectivity = sel ? null : v),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: GoogleFonts.dmSans(
                      color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12),
                  side: BorderSide(color: sel ? AppTheme.primary : AppTheme.divider),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            _Label('EMOTIONAL AFTERMATH'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _aftermathLevels.map((v) {
                final sel = _aftermath == v;
                return ChoiceChip(
                  label: Text(v),
                  selected: sel,
                  onSelected: (_) => setState(() => _aftermath = sel ? null : v),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: GoogleFonts.dmSans(
                      color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12),
                  side: BorderSide(color: sel ? AppTheme.primary : AppTheme.divider),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text('SUBMIT STORY 📖',
                        style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
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
        hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary.withOpacity(0.5)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

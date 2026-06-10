import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gem_provider.dart';

class AddGemScreen extends StatefulWidget {
  const AddGemScreen({super.key});

  @override
  State<AddGemScreen> createState() => _AddGemScreenState();
}

class _AddGemScreenState extends State<AddGemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _category = Gem.categories.first;
  String? _difficulty;
  String? _bestTime;
  LatLng? _pickedLatLng;
  bool _submitting = false;

  static const _difficulties = ['Easy', 'Moderate', 'Hard', 'Expert'];
  static const _bestTimes = [
    'Jan–Mar', 'Apr–Jun', 'Jul–Sep', 'Oct–Dec',
    'Year-round', 'Dry season', 'Avoid monsoon',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to drop a pin first')),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      context.go('/auth?redirect=/drop-gem');
      return;
    }

    setState(() => _submitting = true);
    final ok = await context.read<GemProvider>().addGem(
      userId: auth.user!.id,
      gemName: _nameCtrl.text.trim(),
      category: _category,
      latitude: _pickedLatLng!.latitude,
      longitude: _pickedLatLng!.longitude,
      gemLocation: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      difficulty: _difficulty,
      bestTimeToVisit: _bestTime,
    );
    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gem dropped! 💎')),
        );
        context.go('/explore');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save gem')),
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
        title: Text('DROP A GEM', style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Map picker
            _SectionLabel('PIN LOCATION'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: const LatLng(14.0, 108.0),
                    initialZoom: 5.0,
                    onTap: (_, latlng) => setState(() => _pickedLatLng = latlng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.explorife.app',
                    ),
                    if (_pickedLatLng != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pickedLatLng!,
                          width: 44, height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.push_pin, color: Colors.white, size: 20),
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _pickedLatLng == null
                  ? 'Tap to place your gem on the map'
                  : '${_pickedLatLng!.latitude.toStringAsFixed(4)}, ${_pickedLatLng!.longitude.toStringAsFixed(4)}',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),

            // Gem name
            _SectionLabel('GEM NAME *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _inputDeco('e.g. Secret Waterfall Trail'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Category
            _SectionLabel('CATEGORY *'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: Gem.categories.map((cat) {
                final sel = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? AppTheme.primary : AppTheme.divider),
                    ),
                    child: Text(
                      '${Gem.categoryEmoji[cat]}  ${cat[0].toUpperCase()}${cat.substring(1)}',
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

            // Location name
            _SectionLabel('LOCATION NAME'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationCtrl,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _inputDeco('e.g. Da Lat, Vietnam'),
            ),
            const SizedBox(height: 16),

            // Description
            _SectionLabel('DESCRIPTION'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
              decoration: _inputDeco('Share what makes this place special...'),
            ),
            const SizedBox(height: 16),

            // Difficulty
            _SectionLabel('DIFFICULTY'),
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
            const SizedBox(height: 16),

            // Best time
            _SectionLabel('BEST TIME TO VISIT'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _bestTimes.map((t) {
                final sel = _bestTime == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: sel,
                  onSelected: (_) => setState(() => _bestTime = sel ? null : t),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: GoogleFonts.dmSans(
                    color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 13),
                  side: BorderSide(color: sel ? AppTheme.primary : AppTheme.divider),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Submit
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
                    : Text('DROP GEM 💎', style: GoogleFonts.bebasNeue(fontSize: 20, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary.withOpacity(0.5)),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: GoogleFonts.jetBrainsMono(
        fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 0.8));
  }
}

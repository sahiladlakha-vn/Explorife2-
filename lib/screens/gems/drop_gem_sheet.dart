import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../models/gem_draft.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gem_provider.dart';

/// Slides the "fill in the gem" form up as a modal bottom sheet over whatever
/// is behind it (the placement map / explore screen). Returns true if a gem
/// was published.
Future<bool?> showDropGemSheet(
  BuildContext context, {
  required double lat,
  required double lng,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DropGemSheet(lat: lat, lng: lng),
  );
}

/// Step 3 of the Drop a Gem flow, presented as a draggable bottom sheet:
/// collect name, category, a cover photo, tagline and description for the
/// point chosen in [PlacementScreen], then publish.
///
/// NOTE: this is the gem *creation* form. Not to be confused with
/// [GemDetailScreen] in gem_detail_screen.dart, which is the read-only viewer.
class DropGemSheet extends StatefulWidget {
  final double lat;
  final double lng;

  const DropGemSheet({super.key, required this.lat, required this.lng});

  @override
  State<DropGemSheet> createState() => _DropGemSheetState();
}

class _DropGemSheetState extends State<DropGemSheet> {
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _picker = ImagePicker();
  final GeocodingService _geo = GeocodingService();

  String _category = Gem.categories.first;
  XFile? _cover;
  Uint8List? _coverBytes;
  bool _publishing = false;
  String? _address;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_refresh);
    _taglineCtrl.addListener(_refresh);
    _descCtrl.addListener(_refresh);
    _loadAddress();
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Builds an immutable snapshot of the form for validation / publishing.
  /// All form logic lives in [GemDraft], keeping this widget a thin view.
  GemDraft _buildDraft() => GemDraft(
        name: _nameCtrl.text,
        category: _category,
        lat: widget.lat,
        lng: widget.lng,
        tagline: _taglineCtrl.text,
        description: _descCtrl.text,
        address: _address,
        hasPhoto: _cover != null,
      );

  bool get _canPublish => !_publishing && _buildDraft().canPublish;

  // Reverse-geocode the dropped point to a human address (best effort).
  Future<void> _loadAddress() async {
    final place = await _geo.reverse(widget.lat, widget.lng, types: 'address');
    final name = place?.fullName;
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => _address = name);
    }
  }

  String get _coordLabel => GemDraft.formatCoordinates(widget.lat, widget.lng);

  Future<void> _pickCover() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (mounted) {
        setState(() {
          _cover = x;
          _coverBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open photo picker')),
        );
      }
    }
  }

  Future<void> _publish() async {
    final draft = _buildDraft();
    if (!draft.canPublish || _publishing) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      Navigator.of(context).pop();
      context.go('/auth?redirect=/drop-gem');
      return;
    }

    setState(() => _publishing = true);
    final result = await context.read<GemProvider>().publish(
          draft,
          userId: auth.user!.id,
          photo: _cover,
        );

    if (!mounted) return;
    setState(() => _publishing = false);
    if (result.success) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.photoFailed
              ? 'Gem dropped! (photo couldn’t be uploaded)'
              : 'Gem dropped!'),
        ),
      );
      context.go('/explore');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to publish gem')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              _header(),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  children: [
                    // 01 — Gem name
                    const _NumLabel(num: '01', title: 'GEM NAME', req: true),
                    const SizedBox(height: 10),
                    _field(_nameCtrl, 'e.g. Hidden Rooftop, Bình Thạnh'),
                    const SizedBox(height: 24),

                    // 02 — Category
                    const _NumLabel(num: '02', title: 'CATEGORY', req: true),
                    const SizedBox(height: 12),
                    _categoryGrid(),
                    const SizedBox(height: 24),

                    // 03 — Cover photo
                    const _NumLabel(num: '03', title: 'COVER PHOTO'),
                    const SizedBox(height: 10),
                    _coverPicker(),
                    const SizedBox(height: 24),

                    // 04 — Tagline
                    _NumLabel(
                      num: '04',
                      title: 'TAGLINE',
                      counter:
                          '${_taglineCtrl.text.characters.length}/${GemDraft.maxTaglineLength}',
                    ),
                    const SizedBox(height: 10),
                    _field(_taglineCtrl, 'One line. Make it field-report crisp.',
                        maxLength: GemDraft.maxTaglineLength),
                    const SizedBox(height: 24),

                    // 05 — Description
                    _NumLabel(
                      num: '05',
                      title: 'DESCRIPTION',
                      counter:
                          '${_descCtrl.text.characters.length}/${GemDraft.maxDescriptionLength}',
                    ),
                    const SizedBox(height: 10),
                    _field(_descCtrl, 'What makes it worth the pin. Local intel only.',
                        maxLines: 5, maxLength: GemDraft.maxDescriptionLength),
                    const SizedBox(height: 28),

                    // Publish
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _canPublish ? _publish : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          disabledBackgroundColor:
                              AppTheme.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _publishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Drop the gem',
                                style: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── header: coordinate + reverse-geocoded address + close ──
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _coordLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _address ?? 'Locating address…',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: const Color(0xFF555555),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E2E2)),
              ),
              child: const Icon(Icons.close, color: Color(0xFF555555), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── light text field with hidden default counter ──
  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1, int? maxLength}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
          null,
      style: GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF111111)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(
            fontSize: 15, color: const Color(0xFFAAAAAA)),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E6E6))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E6E6))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }

  // ── 4-column category grid ──
  Widget _categoryGrid() {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: Gem.categories.map((cat) {
        final sel = _category == cat;
        return GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: Container(
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFFF1E8) : const Color(0xFFF6F6F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel ? AppTheme.primary : const Color(0xFFE6E6E6),
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(GemCategories.iconFor(cat),
                    size: 26,
                    color: sel ? AppTheme.primary : const Color(0xFF777777)),
                const SizedBox(height: 8),
                Text(
                  cat.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: sel ? AppTheme.primary : const Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── cover photo upload box ──
  Widget _coverPicker() {
    if (_coverBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Image.memory(_coverBytes!,
                width: double.infinity, height: 180, fit: BoxFit.cover),
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: () => setState(() {
                  _cover = null;
                  _coverBytes = null;
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD9D9D9)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_outlined,
                size: 34, color: Color(0xFF999999)),
            const SizedBox(height: 12),
            Text('TAP TO UPLOAD',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: const Color(0xFF777777))),
            const SizedBox(height: 6),
            Text('JPG · PNG · HEIC · Max 12MB',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: const Color(0xFFAAAAAA))),
          ],
        ),
      ),
    );
  }
}

/// Numbered section header: "01  GEM NAME  [REQ] ——————  0/80"
class _NumLabel extends StatelessWidget {
  final String num;
  final String title;
  final bool req;
  final String? counter;
  const _NumLabel({
    required this.num,
    required this.title,
    this.req = false,
    this.counter,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(num,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary)),
        const SizedBox(width: 10),
        Text(title,
            style: GoogleFonts.bebasNeue(
                fontSize: 19,
                letterSpacing: 0.5,
                color: const Color(0xFF111111))),
        if (req) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.6)),
            ),
            child: Text('REQ',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: Container(height: 1, color: const Color(0xFFECECEC)),
        ),
        if (counter != null) ...[
          const SizedBox(width: 10),
          Text(counter!,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: const Color(0xFFAAAAAA))),
        ],
      ],
    );
  }
}

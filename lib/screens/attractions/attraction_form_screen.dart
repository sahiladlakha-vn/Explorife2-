import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/poi_dedup.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attraction.dart';
import '../../models/gem.dart';
import '../../models/role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gem_provider.dart';
import '../../repositories/attraction_repository.dart';
import '../../repositories/gem_repository.dart';

/// Business Owner-facing create/edit form for an Attraction listing. Create
/// mode when [existing] is null, edit mode otherwise (prefills every field;
/// verification-status fields are never editable here — see the DB
/// trigger's own doc comment for why that's enforced server-side too, not
/// just by this form omitting the field).
///
/// Role enforcement: RLS is the real gate (`business owners can insert own
/// attractions` requires `profiles.role = 'business_owner'`) — the check in
/// [build] below is a fast, honest "you can't do this" message rather than
/// letting a non-Business-Owner fill out the whole form and only find out
/// at submit time that the insert was silently rejected by RLS.
class AttractionFormScreen extends StatefulWidget {
  const AttractionFormScreen({super.key, this.existing});

  final Attraction? existing;

  @override
  State<AttractionFormScreen> createState() => _AttractionFormScreenState();
}

class _AttractionFormScreenState extends State<AttractionFormScreen> {
  late final _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _addressCtrl =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _hoursCtrl =
      TextEditingController(text: widget.existing?.openingHours ?? '');
  late final _descCtrl =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _durationCtrl =
      TextEditingController(text: widget.existing?.recommendedDuration ?? '');
  late final _feeAmountCtrl = TextEditingController(
      text: widget.existing?.entryFeeAmount?.toString() ?? '');

  late String _category = widget.existing?.category ?? Gem.categories.first;
  late EntryFeeType _feeType =
      widget.existing?.entryFeeType ?? EntryFeeType.free;

  late double? _lat = widget.existing?.latitude;
  late double? _lng = widget.existing?.longitude;
  bool _resolvingAddress = false;
  String? _addressError;

  final _picker = ImagePicker();
  final List<String> _existingGallery = [];
  final List<XFile> _newPhotos = [];
  final List<Uint8List> _newPhotoBytes = [];

  /// Set once the user confirms (or declines) linking to a matched Gem —
  /// null means "not yet asked" (still shows the prompt on submit); a
  /// declined match stores the empty string sentinel `''` so re-submitting
  /// doesn't re-prompt for the exact same match.
  String? _confirmedGemId;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _existingGallery.addAll(widget.existing?.gallery ?? const []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _hoursCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _feeAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress() async {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) return;
    setState(() {
      _resolvingAddress = true;
      _addressError = null;
    });
    final results = await GeocodingService()
        .search(address, types: 'address,poi,place,locality,neighborhood');
    if (!mounted) return;
    final place = results.where((p) => p.hasCoords).firstOrNull;
    setState(() {
      _resolvingAddress = false;
      if (place == null) {
        _addressError = "Couldn't find that address — try adding more detail.";
        _lat = null;
        _lng = null;
      } else {
        _lat = place.lat;
        _lng = place.lng;
      }
    });
  }

  Future<void> _addPhotos() async {
    final remaining = 8 - (_existingGallery.length + _newPhotos.length);
    if (remaining <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    for (final file in picked) {
      _newPhotoBytes.add(await file.readAsBytes());
    }
    setState(() => _newPhotos.addAll(picked));
  }

  void _removeNewPhotoAt(int i) {
    setState(() {
      _newPhotos.removeAt(i);
      _newPhotoBytes.removeAt(i);
    });
  }

  void _removeExistingPhotoAt(int i) {
    setState(() => _existingGallery.removeAt(i));
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null &&
      _hoursCtrl.text.trim().isNotEmpty &&
      _descCtrl.text.trim().isNotEmpty &&
      (_feeType == EntryFeeType.free || _feeAmountCtrl.text.trim().isNotEmpty);

  Future<void> _submit(BuildContext context) async {
    if (!_canSubmit || _submitting) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    // "This looks like an existing place — link it?" — only asked once per
    // session for a given match (see _confirmedGemId's doc comment), and
    // only for a NEW listing (an edit already has whatever gemId it had).
    String? gemId = widget.existing?.gemId;
    if (widget.existing == null && _confirmedGemId == null) {
      final match = findLikelyGemMatch(
        context.read<GemProvider>().allGems,
        name: _nameCtrl.text.trim(),
        lat: _lat!,
        lng: _lng!,
      );
      if (match != null) {
        final shouldLink = await _confirmGemMatch(context, match);
        if (!mounted) return;
        setState(() => _confirmedGemId = shouldLink ? match.id : '');
        gemId = shouldLink ? match.id : null;
      } else {
        _confirmedGemId = '';
      }
    } else if (_confirmedGemId != null && _confirmedGemId!.isNotEmpty) {
      gemId = _confirmedGemId;
    }

    setState(() => _submitting = true);
    try {
      final uploaded = _newPhotos.isEmpty
          ? <String>[]
          : await GemRepository().uploadPhotos(userId, _newPhotos);
      final gallery = [..._existingGallery, ...uploaded];

      final attraction = Attraction(
        id: widget.existing?.id ?? '',
        ownerId: userId,
        gemId: gemId,
        name: _nameCtrl.text.trim(),
        category: _category,
        gallery: gallery,
        address: _addressCtrl.text.trim(),
        latitude: _lat!,
        longitude: _lng!,
        openingHours: _hoursCtrl.text.trim(),
        entryFeeType: _feeType,
        entryFeeAmount:
            _feeType == EntryFeeType.paid ? int.tryParse(_feeAmountCtrl.text.trim()) : null,
        description: _descCtrl.text.trim(),
        recommendedDuration:
            _durationCtrl.text.trim().isEmpty ? null : _durationCtrl.text.trim(),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      final repo = AttractionRepository();
      if (widget.existing == null) {
        await repo.create(attraction);
      } else {
        await repo.update(attraction);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.existing == null
            ? 'Listing submitted — pending verification'
            : 'Listing updated'),
      ));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save listing: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmGemMatch(BuildContext context, Gem match) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Existing place found'),
        content: Text(
            'This looks like an existing place in Explorife: "${match.gemName}". '
            'Link your listing to it?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, keep separate')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, link it')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role;
    if (role != Role.businessOwner) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface),
        body: Center(
          child: Text('Only Business Owner accounts can list an Attraction.',
              style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        title: Text(widget.existing == null ? 'List an Attraction' : 'Edit Listing'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _sectionLabel('IDENTITY'),
          _textField(_nameCtrl, 'Name', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _categoryDropdown(),
          const SizedBox(height: 12),
          _gallerySection(),
          const SizedBox(height: 24),
          _sectionLabel('LOCATION & ACCESS'),
          _textField(_addressCtrl, 'Address', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _resolvingAddress ? null : _resolveAddress,
              icon: _resolvingAddress
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 16),
              label: const Text('Find location'),
            ),
            if (_lat != null && _lng != null) ...[
              const SizedBox(width: 10),
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 4),
              const Text('Location found', style: TextStyle(fontSize: 12, color: Colors.green)),
            ],
          ]),
          if (_addressError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_addressError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          _textField(_hoursCtrl, 'Opening Hours (e.g. "9am–5pm daily")',
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          _entryFeeSection(),
          const SizedBox(height: 24),
          _sectionLabel('DETAILS & SAFETY'),
          _textField(_descCtrl, 'Description',
              maxLines: 5, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _textField(_durationCtrl, 'Recommended Duration (optional)'),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canSubmit && !_submitting ? () => _submit(context) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(widget.existing == null ? 'Submit for Verification' : 'Save Changes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: AppTheme.lightMute, letterSpacing: 0.5)),
      );

  Widget _textField(TextEditingController ctrl, String label,
      {int maxLines = 1, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.lightCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _category,
      decoration: InputDecoration(
        labelText: 'Category',
        filled: true,
        fillColor: AppTheme.lightCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final c in Gem.categories)
          DropdownMenuItem(
            value: c,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(GemCategories.iconFor(c), size: 16),
              const SizedBox(width: 8),
              Text(c[0].toUpperCase() + c.substring(1)),
            ]),
          ),
      ],
      onChanged: (v) => setState(() => _category = v ?? _category),
    );
  }

  Widget _entryFeeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entry Fee', style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(
            label: const Text('Free'),
            selected: _feeType == EntryFeeType.free,
            onSelected: (_) => setState(() => _feeType = EntryFeeType.free),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Paid'),
            selected: _feeType == EntryFeeType.paid,
            onSelected: (_) => setState(() => _feeType = EntryFeeType.paid),
          ),
        ]),
        if (_feeType == EntryFeeType.paid) ...[
          const SizedBox(height: 12),
          _textField(_feeAmountCtrl, 'Amount (VND)', onChanged: (_) => setState(() {})),
        ],
      ],
    );
  }

  Widget _gallerySection() {
    final total = _existingGallery.length + _newPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _existingGallery.length; i++)
                _photoThumb(
                  networkUrl: _existingGallery[i],
                  onRemove: () => _removeExistingPhotoAt(i),
                ),
              for (var i = 0; i < _newPhotoBytes.length; i++)
                _photoThumb(
                  bytes: _newPhotoBytes[i],
                  onRemove: () => _removeNewPhotoAt(i),
                ),
              if (total < 8)
                GestureDetector(
                  onTap: _addPhotos,
                  child: Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.lightCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.lightBorder),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: AppTheme.lightMute),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _photoThumb({String? networkUrl, Uint8List? bytes, required VoidCallback onRemove}) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 80,
              height: 80,
              child: networkUrl != null
                  ? Image.network(networkUrl, fit: BoxFit.cover)
                  : Image.memory(bytes!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

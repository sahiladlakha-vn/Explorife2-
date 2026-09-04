import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/poi_dedup.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gem.dart';
import '../../models/restaurant.dart';
import '../../models/role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gem_provider.dart';
import '../../repositories/gem_repository.dart';
import '../../repositories/restaurant_repository.dart';

const _cuisineTypeOptions = [
  'Local', 'International', 'Seafood', 'Vegan', 'Street Food', 'Fine Dining'
];
const _dietaryOptions = ['Vegan', 'Halal', 'Vegetarian', 'Gluten-free'];

/// Business Owner-facing create/edit form for a Restaurant listing —
/// mirrors AttractionFormScreen's structure exactly (same role gate, same
/// Gem-linking confirm dialog via findLikelyGemMatch, same
/// verification-fields-never-editable-here contract). See
/// docs/audits/restaurant-business-profile-2026-09-05.md for what's
/// actually different: cuisineType/dietaryOptions are separate multi-select
/// tags (not the fixed 'food' category), reservationOption is a plain
/// informational toggle with no booking action, and businessLicenseUrl has
/// deliberately no form field here — same "field exists, no authoring UI
/// yet" convention Attraction's certification_urls already established (an
/// admin can populate it directly).
class RestaurantFormScreen extends StatefulWidget {
  const RestaurantFormScreen({super.key, this.existing});

  final Restaurant? existing;

  @override
  State<RestaurantFormScreen> createState() => _RestaurantFormScreenState();
}

class _RestaurantFormScreenState extends State<RestaurantFormScreen> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _addressCtrl =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.existing?.phone ?? '');
  late final _hoursCtrl =
      TextEditingController(text: widget.existing?.openingHours ?? '');

  final Set<String> _cuisineType = {};
  final Set<String> _dietary = {};
  late PriceRange _priceRange = widget.existing?.priceRange ?? PriceRange.low;
  late bool _reservationOption = widget.existing?.reservationOption ?? false;

  late double? _lat = widget.existing?.latitude;
  late double? _lng = widget.existing?.longitude;
  bool _resolvingAddress = false;
  String? _addressError;

  final _picker = ImagePicker();
  final List<String> _existingGallery = [];
  final List<XFile> _newPhotos = [];
  final List<Uint8List> _newPhotoBytes = [];

  final List<_DraftMenuItem> _menuItems = [];
  bool _menuLoaded = false;

  /// Same "asked once per session" sentinel as AttractionFormScreen —
  /// null means not yet asked, empty string means declined/no match found.
  String? _confirmedGemId;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _existingGallery.addAll(widget.existing?.gallery ?? const []);
    _cuisineType.addAll(widget.existing?.cuisineType ?? const []);
    _dietary.addAll(widget.existing?.dietaryOptions ?? const []);
    if (widget.existing != null) {
      _loadMenuItems(widget.existing!.id);
    } else {
      _menuLoaded = true;
    }
  }

  Future<void> _loadMenuItems(String restaurantId) async {
    final items = await RestaurantRepository().fetchMenuItems(restaurantId);
    if (!mounted) return;
    setState(() {
      _menuItems.addAll(items.map((i) => _DraftMenuItem(
            dishName: i.dishName,
            priceAmount: i.priceAmount,
            photoUrl: i.photoUrl,
          )));
      _menuLoaded = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _hoursCtrl.dispose();
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

  Future<void> _addMenuItem() async {
    final draft = await showDialog<_DraftMenuItem>(
      context: context,
      builder: (ctx) => const _MenuItemDialog(),
    );
    if (draft != null) setState(() => _menuItems.add(draft));
  }

  void _removeMenuItemAt(int i) => setState(() => _menuItems.removeAt(i));

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null &&
      _phoneCtrl.text.trim().isNotEmpty &&
      _hoursCtrl.text.trim().isNotEmpty;

  Future<void> _submit(BuildContext context) async {
    if (!_canSubmit || _submitting) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

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

      final restaurant = Restaurant(
        id: widget.existing?.id ?? '',
        ownerId: userId,
        gemId: gemId,
        name: _nameCtrl.text.trim(),
        cuisineType: _cuisineType.toList(),
        priceRange: _priceRange,
        gallery: gallery,
        address: _addressCtrl.text.trim(),
        latitude: _lat!,
        longitude: _lng!,
        phone: _phoneCtrl.text.trim(),
        openingHours: _hoursCtrl.text.trim(),
        dietaryOptions: _dietary.toList(),
        reservationOption: _reservationOption,
        businessLicenseUrl: widget.existing?.businessLicenseUrl,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      final repo = RestaurantRepository();
      final String restaurantId;
      if (widget.existing == null) {
        restaurantId = (await repo.create(restaurant)).id;
      } else {
        restaurantId = widget.existing!.id;
        await repo.update(restaurant);
      }
      await repo.replaceMenuItems(
        restaurantId,
        _menuItems
            .map((d) => RestaurantMenuItem(
                  id: '',
                  restaurantId: restaurantId,
                  dishName: d.dishName,
                  priceAmount: d.priceAmount,
                  photoUrl: d.photoUrl,
                ))
            .toList(),
      );

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
          child: Text('Only Business Owner accounts can list a Restaurant.',
              style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        title: Text(widget.existing == null ? 'List a Restaurant' : 'Edit Listing'),
      ),
      body: !_menuLoaded
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _sectionLabel('IDENTITY'),
                _textField(_nameCtrl, 'Name', onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                _chipMultiSelect('Cuisine Type', _cuisineTypeOptions, _cuisineType),
                const SizedBox(height: 12),
                _priceRangeSelector(),
                const SizedBox(height: 12),
                _gallerySection(),
                const SizedBox(height: 24),
                _sectionLabel('LOCATION & CONTACT'),
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
                _textField(_phoneCtrl, 'Phone', onChanged: (_) => setState(() {})),
                const SizedBox(height: 16),
                _textField(_hoursCtrl, 'Opening Hours (e.g. "9am–10pm daily")',
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 24),
                _sectionLabel('OFFERINGS'),
                _menuSection(),
                const SizedBox(height: 16),
                _chipMultiSelect('Dietary Options', _dietaryOptions, _dietary),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Accepts reservations'),
                  subtitle: const Text(
                      'Informational only — shown to travellers as "Reservations '
                      'accepted" or "Walk-ins only." Not a booking action.',
                      style: TextStyle(fontSize: 12)),
                  value: _reservationOption,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _reservationOption = v),
                ),
                const SizedBox(height: 24),
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

  Widget _chipMultiSelect(String label, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              FilterChip(
                label: Text(o),
                selected: selected.contains(o),
                onSelected: (v) => setState(() {
                  if (v) {
                    selected.add(o);
                  } else {
                    selected.remove(o);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _priceRangeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Price Range', style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final p in PriceRange.values)
              ChoiceChip(
                label: Text(p.wire),
                selected: _priceRange == p,
                onSelected: (_) => setState(() => _priceRange = p),
              ),
          ],
        ),
      ],
    );
  }

  Widget _gallerySection() {
    final total = _existingGallery.length + _newPhotos.length;
    return SizedBox(
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

  Widget _menuSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Menu Highlights', style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightMute)),
        const SizedBox(height: 8),
        for (var i = 0; i < _menuItems.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.lightCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${_menuItems[i].dishName} — ${_menuItems[i].priceAmount} VND',
                      style: GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
                ),
                GestureDetector(
                  onTap: () => _removeMenuItemAt(i),
                  child: const Icon(Icons.close, size: 18, color: AppTheme.lightMute),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addMenuItem,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add dish'),
        ),
      ],
    );
  }
}

class _DraftMenuItem {
  _DraftMenuItem({required this.dishName, required this.priceAmount, this.photoUrl});
  final String dishName;
  final int priceAmount;
  final String? photoUrl;
}

/// A dish's photo, if the owner adds one, uploads through the same
/// GemRepository.uploadPhotos path the gallery above uses — no separate
/// upload infra for menu-item photos.
class _MenuItemDialog extends StatefulWidget {
  const _MenuItemDialog();

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _uploading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = file;
      _photoBytes = bytes;
    });
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && int.tryParse(_priceCtrl.text.trim()) != null;

  Future<void> _save(BuildContext context) async {
    if (!_canSave || _uploading) return;
    final userId = context.read<AuthProvider>().user?.id;
    String? photoUrl;
    if (_photo != null && userId != null) {
      setState(() => _uploading = true);
      final uploaded = await GemRepository().uploadPhotos(userId, [_photo!]);
      photoUrl = uploaded.firstOrNull;
      if (!context.mounted) return;
    }
    Navigator.pop(
      context,
      _DraftMenuItem(
        dishName: _nameCtrl.text.trim(),
        priceAmount: int.parse(_priceCtrl.text.trim()),
        photoUrl: photoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a dish'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Dish name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price (VND)'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.lightCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: _photoBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_photoBytes!, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.add_a_photo_outlined, color: AppTheme.lightMute),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _canSave && !_uploading ? () => _save(context) : null,
          child: _uploading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}

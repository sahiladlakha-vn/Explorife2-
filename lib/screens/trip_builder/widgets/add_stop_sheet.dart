import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../widgets/app_network_image.dart';

// Add-stop sheet for the itinerary day builder — replaces the old
// drag-from-Discovery + per-slot "+ Custom" mechanics with a single
// tap-to-select bottom sheet (slot + time + search/browse + custom-stop
// fallback). See the paired itinerary-upgrade work for rendering; this file
// is the add-stop *interaction* only.
//
// MODEL DIFF: none. Confirmed in the Phase 0 audit — Gem already carries
// photoUrl/category/estDurationMin (the last added earlier this session for
// the paired Itinerary prompt), and TripProvider.addStop already accepts
// either a gemId or a customPayload title, computing sortOrder as
// stops.where(day && slot).length (append-to-end). Nothing here needed a new
// column or a new provider method.
//
// DISCOVERY QUERY: below is not a new query — it's locationFilteredGems /
// gemMatchesSearch, relocated verbatim from discovery_panel.dart (which is
// being retired along with discovery_sheet.dart/asset_card.dart/asset_data.dart
// now that tap replaces drag as the only attach path — see the audit's
// decision log). "Nearby" stays the existing text-match-against-trip.location
// behavior, not a geo radius: trips have no lat/lng, and the app's one real
// distance mechanism (GemProvider.nearbyGems) is anchored to live device GPS,
// the wrong anchor for planning a trip to a different city — confirmed with
// the user rather than silently geocoding trip.location on the fly.

/// Below this many location-tagged matches, discovery gives up on the
/// location filter and shows the whole catalogue (with a banner). A trip
/// whose city has only one or two tagged gems is better served by the full
/// list than by a near-empty sheet — the user came here to *build*, not to
/// admire scarcity.
const int locationFallbackThreshold = 3;

/// Case-insensitive name/tagline/description match.
bool gemMatchesSearch(Gem g, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return g.gemName.toLowerCase().contains(q) ||
      (g.tagline?.toLowerCase().contains(q) ?? false) ||
      (g.description?.toLowerCase().contains(q) ?? false);
}

/// Filters [source] to gems whose location contains every token of
/// [location] (whitespace-split, case-insensitive). If fewer than
/// [locationFallbackThreshold] match, returns the full [source] with
/// `fellBack: true` and the count that *would* have matched — the caller
/// shows a banner and asks rows to annotate their location.
({List<Gem> gems, bool fellBack, int matched}) locationFilteredGems(
    List<Gem> source, String? location) {
  // TODO(gemsIn): this token-substring match runs client-side over the whole
  // catalogue. Promote to a pure GemProvider.gemsIn(location) read once gems
  // are queried server-side, keeping the fallback-threshold logic here.
  if (location == null || location.trim().isEmpty) {
    return (gems: source, fellBack: false, matched: source.length);
  }
  final tokens = location.toLowerCase().split(RegExp(r'\s+'));
  final local = source.where((g) {
    final loc = g.gemLocation?.toLowerCase();
    if (loc == null || loc.isEmpty) return false;
    return tokens.every(loc.contains);
  }).toList();
  if (local.length < locationFallbackThreshold) {
    return (gems: source, fellBack: true, matched: local.length);
  }
  return (gems: local, fellBack: false, matched: local.length);
}

/// Display label + icon for a slot key. Single source so the slot header
/// (itinerary_canvas.dart's `_SlotHeader`) and this sheet's slot picker
/// agree — itinerary_canvas.dart already imports this file for
/// [AddStopSheet], so this lives here rather than the reverse (avoids a
/// circular import).
(String, IconData) slotMeta(String slot) {
  switch (slot) {
    case 'morning':
      return ('Morning', Icons.wb_twilight);
    case 'afternoon':
      return ('Afternoon', Icons.wb_sunny_outlined);
    case 'evening':
      return ('Evening', Icons.nightlight_round);
    default:
      return (slot, Icons.schedule);
  }
}

/// Color roles this sheet needs, resolved once per [AddStopSheet.light] and
/// threaded down to every child widget below — lets the same sheet render in
/// Trip Builder's dark theme or My Trip's light theme without duplicating
/// the widget tree. `primary`/`primarySoft` aren't included: the orange
/// accent is identical in both themes (AppTheme.primary), so those stay
/// direct references at each call site.
class _SheetPalette {
  final Color surface; // sheet container + footer background
  final Color card; // fields/chips/thumb-fallback background
  final Color border;
  final Color ink; // primary text
  final Color mute; // secondary/placeholder text

  const _SheetPalette({
    required this.surface,
    required this.card,
    required this.border,
    required this.ink,
    required this.mute,
  });

  static const dark = _SheetPalette(
    surface: AppTheme.surface,
    card: AppTheme.surface2,
    border: AppTheme.divider,
    ink: AppTheme.textPrimary,
    mute: AppTheme.textSecondary,
  );

  // Same hex values as My Trip's private _kPage/_kCard/_kBorder/_kInk/_kMute
  // (profile_palette.dart) — using the public AppTheme.light* aliases here
  // instead of importing those library-private constants across files.
  static const light = _SheetPalette(
    surface: AppTheme.lightSurface,
    card: AppTheme.lightCard,
    border: AppTheme.lightBorder,
    ink: AppTheme.lightInk,
    mute: AppTheme.lightMute,
  );
}

/// Tap-to-search-and-select add-stop sheet: slot + time, a debounced
/// search/category-filtered nearby-gem list, and a custom-stop fallback.
/// Single-select — tapping a result (or entering a custom name) is the whole
/// interaction; drag-and-drop is retired along with the standalone Discovery
/// panel/sheet (see this file's header comment for the audit's reasoning).
class AddStopSheet extends StatefulWidget {
  const AddStopSheet({
    super.key,
    required this.tripId,
    required this.day,
    required this.initialSlot,
    this.light = false,
  });

  final String tripId;
  final int day;
  final String initialSlot;

  /// True when opened from a light-themed surface (My Trip's Itinerary tab);
  /// false (default) renders Trip Builder's original dark theme, unchanged.
  final bool light;

  @override
  State<AddStopSheet> createState() => _AddStopSheetState();
}

class _AddStopSheetState extends State<AddStopSheet> {
  late String _slot = widget.initialSlot;
  String? _time;
  final _searchCtrl = TextEditingController();
  final _customNameCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _activeCategory = 'all';
  Gem? _selectedGem;
  bool _customMode = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _customNameCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  void _selectGem(Gem g) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedGem = _selectedGem?.id == g.id ? null : g; // tap again to deselect
      if (_selectedGem != null) _customMode = false;
    });
  }

  void _toggleCustomMode() {
    setState(() {
      _customMode = !_customMode;
      if (_customMode) _selectedGem = null;
    });
  }

  bool get _canAdd =>
      _selectedGem != null ||
      (_customMode && _customNameCtrl.text.trim().isNotEmpty);

  // Fire-and-forget: addStop is optimistic and self-rolls-back on error,
  // same convention as every other stop mutation in this app (TimeSlotBlock's
  // old drag-drop, the itinerary segment's edit sheet, etc.).
  void _confirm() {
    if (!_canAdd) return;
    HapticFeedback.mediumImpact();
    if (_selectedGem != null) {
      context.read<TripProvider>().addStop(
            tripId: widget.tripId,
            day: widget.day,
            slot: _slot,
            gemId: _selectedGem!.id,
            startTime: _time,
          );
    } else {
      context.read<TripProvider>().addStop(
            tripId: widget.tripId,
            day: widget.day,
            slot: _slot,
            customPayload: {'title': _customNameCtrl.text.trim()},
            startTime: _time,
          );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.light ? _SheetPalette.light : _SheetPalette.dark;
    final location = context.select<TripProvider, String?>(
        (p) => p.tripById(widget.tripId)?.location);
    final allGems = context.watch<GemProvider>().allGems;
    final located = locationFilteredGems(allGems, location);
    final filtered = located.gems.where((g) {
      final catOk = _activeCategory == 'all' ||
          g.category?.toLowerCase() == _activeCategory;
      return catOk && gemMatchesSearch(g, _query);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                  color: palette.border, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Text('Add to Day ${widget.day}',
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  // --- 1. Slot ---
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const ['morning', 'afternoon', 'evening'])
                        _SlotChip(
                          slot: s,
                          selected: _slot == s,
                          palette: palette,
                          onTap: () => setState(() => _slot = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // --- 2. Time ---
                  GestureDetector(
                    onTap: _pickTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(children: [
                        Icon(Icons.access_time, size: 18, color: palette.mute),
                        const SizedBox(width: 10),
                        Text(_time ?? 'Set a time',
                            style: TextStyle(
                                fontSize: 14,
                                color: _time == null ? palette.mute : palette.ink)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- 3. Discover header + live nearby count ---
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            location != null && location.isNotEmpty
                                ? 'Discover $location'
                                : 'Discover gems',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Text('${filtered.length} nearby',
                          style: TextStyle(
                              color: palette.mute,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // --- 4. Search (debounced ~250ms) ---
                  TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: TextStyle(color: palette.ink, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search gems',
                      hintStyle: TextStyle(color: palette.mute, fontSize: 14),
                      prefixIcon:
                          Icon(Icons.search, color: palette.mute, size: 20),
                      filled: true,
                      fillColor: palette.card,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // --- 5. Category chips ---
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 1 + Gem.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = i == 0 ? 'all' : Gem.categories[i - 1];
                        final selected = c == _activeCategory;
                        final label =
                            c == 'all' ? 'All' : c[0].toUpperCase() + c.substring(1);
                        return GestureDetector(
                          onTap: () => setState(() => _activeCategory = c),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primary : palette.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: selected
                                      ? AppTheme.primary
                                      : palette.border),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    color:
                                        selected ? Colors.white : palette.mute,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (located.fellBack)
                    _FallbackBanner(
                        location: location,
                        matched: located.matched,
                        palette: palette),
                  // --- 6. Results ---
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                            'No gems match. Try clearing filters, or add a custom stop below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.mute, fontSize: 13)),
                      ),
                    )
                  else
                    for (final g in filtered) ...[
                      _GemResultRow(
                        gem: g,
                        selected: _selectedGem?.id == g.id,
                        palette: palette,
                        onTap: () => _selectGem(g),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 4),
                  // --- 7. Custom stop fallback ---
                  GestureDetector(
                    onTap: _toggleCustomMode,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                _customMode ? AppTheme.primary : palette.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                          _customMode
                              ? '− Cancel custom stop'
                              : '+ Add a custom stop',
                          style: TextStyle(
                              color:
                                  _customMode ? AppTheme.primary : palette.mute,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_customMode) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customNameCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: palette.ink, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'What is it? (e.g. Airport taxi)',
                        hintStyle: TextStyle(color: palette.mute, fontSize: 14),
                        filled: true,
                        fillColor: palette.card,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // --- 8. Footer: selection summary + Add to day ---
            _Footer(
              slot: _slot,
              time: _time,
              selectionLabel: _selectedGem?.gemName ??
                  (_customMode && _customNameCtrl.text.trim().isNotEmpty
                      ? _customNameCtrl.text.trim()
                      : null),
              canAdd: _canAdd,
              palette: palette,
              onAdd: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String slot;
  final bool selected;
  final _SheetPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = slotMeta(slot);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : palette.card,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: selected ? AppTheme.primary : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : palette.mute),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : palette.mute,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// One discovery result: thumb, name, and a `category · duration · Cost TBD`
/// meta line. Cost is unconditionally TBD — a gem carries no price of its
/// own (price is per-placed-stop, set after attaching, same as a dropped
/// gem's PriceEditPill) — kept as a static column for prototype visual
/// parity per the resolved Phase 0 decision, not because it varies.
class _GemResultRow extends StatelessWidget {
  const _GemResultRow({
    required this.gem,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final Gem gem;
  final bool selected;
  final _SheetPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      gem.displayCategory,
      if (gem.estDurationMin != null) '${gem.estDurationMin}m',
      'Cost TBD',
    ];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primarySoft : palette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primary : palette.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                color: palette.surface,
                child: (gem.photoUrl != null && gem.photoUrl!.isNotEmpty)
                    ? AppNetworkImage(url: gem.photoUrl!)
                    : Center(
                        child: Text(gem.emoji,
                            style: const TextStyle(fontSize: 20))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gem.gemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(metaParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.mute, fontSize: 11)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner(
      {required this.location, required this.matched, required this.palette});

  final String? location;
  final int matched;
  final _SheetPalette palette;

  @override
  Widget build(BuildContext context) {
    final place = location ?? "this trip's location";
    final lead = matched == 0
        ? 'No gems tagged $place yet.'
        : 'Only $matched gem${matched == 1 ? '' : 's'} tagged $place.';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.public, color: palette.mute, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$lead Showing all gems below.',
                style: TextStyle(color: palette.mute, fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Persistent footer: current selection + slot (+ time if set), and the
/// primary confirm button — disabled until a gem is selected or a custom
/// name is entered.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.slot,
    required this.time,
    required this.selectionLabel,
    required this.canAdd,
    required this.palette,
    required this.onAdd,
  });

  final String slot;
  final String? time;
  final String? selectionLabel;
  final bool canAdd;
  final _SheetPalette palette;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final (slotLabel, _) = slotMeta(slot);
    final summary = selectionLabel == null
        ? 'Pick a gem or add a custom stop'
        : '$selectionLabel · $slotLabel${time != null ? ' · $time' : ''}';
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selectionLabel == null ? palette.mute : palette.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: canAdd ? onAdd : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              disabledBackgroundColor: palette.card,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Add to day',
                style: TextStyle(
                    color: canAdd ? Colors.white : palette.mute,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

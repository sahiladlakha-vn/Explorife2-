import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import 'asset_card.dart';
import 'discovery_panel.dart' show CategoryChipsRow, gemMatchesSearch, locationFilteredGems;

/// Fractional heights of the "half" and "full" snap points, relative to the
/// bounded area the sheet is given (see `TripBuilderScreen`'s mobile layout —
/// that area already excludes the summary peek's height, so `kDiscoverySheetFull`
/// reads as "fill what's left above the peek", not "fill the physical screen").
/// The collapsed extent isn't a fixed fraction — see `_collapsedExtentFor`.
const double kDiscoverySheetHalf = 0.55;
const double kDiscoverySheetFull = 0.94;

/// The collapsed bar's fixed content height in logical pixels — see
/// [_CollapsedBar]. Deriving the collapsed *fraction* from this (rather than
/// guessing a flat fraction like 0.09) means the slim bar always fits its
/// content regardless of device height, instead of clipping on short screens
/// or leaving dead space on tall ones.
const double _kCollapsedContentPx = 48.0;

double _collapsedExtentFor(double areaHeight) =>
    areaHeight <= 0 ? 0.1 : (_kCollapsedContentPx / areaHeight).clamp(0.04, 0.3);

/// Mobile Discover-gems panel, rebuilt as a real draggable bottom sheet with 3
/// snap points instead of a fixed-height pane sitting under the itinerary:
///   - collapsed: a slim tab bar ("Discover gems · N nearby"), itinerary in
///     full view above it.
///   - half (default): ~55% of the available height, rounded top + shadow.
///   - full: fills the available height for focused browsing.
/// Desktop keeps using [DiscoveryPanel] directly (a static left pane) — this
/// widget is mobile-only. Filtering logic (search/category/location fallback)
/// is shared with it via the top-level helpers in discovery_panel.dart so the
/// two never drift.
class DiscoveryBottomSheet extends StatefulWidget {
  const DiscoveryBottomSheet({super.key, required this.tripId});
  final String tripId;

  @override
  State<DiscoveryBottomSheet> createState() => _DiscoveryBottomSheetState();
}

class _DiscoveryBottomSheetState extends State<DiscoveryBottomSheet> {
  final _sheetController = DraggableScrollableController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _activeCategory = 'all';
  // Rest state on landing is collapsed — the itinerary should be in full view
  // the moment the builder opens, not half-covered by Discover. Both fields
  // start at the same rough guess (recomputed every build via
  // [_collapsedExtentFor]) so nothing reads as "half" before the first layout.
  double _extent = 0.1;
  double _collapsedExtent = 0.1;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onExtentChanged);
  }

  void _onExtentChanged() {
    if (!mounted) return;
    setState(() => _extent = _sheetController.size);
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onExtentChanged);
    _sheetController.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Debounced so a fast typist doesn't rebuild the list on every keystroke.
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  bool get _isCollapsed =>
      _extent < (_collapsedExtent + kDiscoverySheetHalf) / 2;

  void _toggleCollapse() {
    _animateTo(_isCollapsed ? kDiscoverySheetHalf : _collapsedExtent);
  }

  void _animateTo(double target) {
    _sheetController.animateTo(target,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  // The handle (and, when collapsed, the whole slim bar) sits outside the
  // list's Scrollable, so DraggableScrollableSheet's built-in drag/scroll
  // coordination — which only listens to the attached scrollController's
  // Scrollable — never sees these gestures. Drive the resize manually instead.
  void _onHandleDragUpdate(DragUpdateDetails details, double areaHeight) {
    if (areaHeight <= 0) return;
    final deltaExtent = -details.delta.dy / areaHeight;
    final next =
        (_sheetController.size + deltaExtent).clamp(_collapsedExtent, kDiscoverySheetFull);
    _sheetController.jumpTo(next);
  }

  void _onHandleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetController.size;
    final snaps = [_collapsedExtent, kDiscoverySheetHalf, kDiscoverySheetFull];
    double target;
    if (velocity < -300) {
      // Flicked up: advance to the next breakpoint above.
      target = snaps.firstWhere((s) => s > current + 0.01, orElse: () => kDiscoverySheetFull);
    } else if (velocity > 300) {
      // Flicked down: drop to the next breakpoint below.
      target = snaps.lastWhere((s) => s < current - 0.01, orElse: () => _collapsedExtent);
    } else {
      // Slow release: snap to whichever breakpoint is closest.
      target = snaps.reduce(
          (a, b) => (a - current).abs() < (b - current).abs() ? a : b);
    }
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final location =
        context.select<TripProvider, String?>((p) => p.activeTrip?.location);
    final allGems = context.watch<GemProvider>().allGems;
    final located = locationFilteredGems(allGems, location);
    final filtered = located.gems.where((g) {
      final catOk =
          _activeCategory == 'all' || g.category?.toLowerCase() == _activeCategory;
      return catOk && gemMatchesSearch(g, _query);
    }).toList();
    final hasFilters = _query.isNotEmpty || _activeCategory != 'all';

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaHeight = constraints.maxHeight;
        _collapsedExtent = _collapsedExtentFor(areaHeight);
        return DraggableScrollableSheet(
          controller: _sheetController,
          // Land collapsed — see the field doc on `_extent` above.
          initialChildSize: _collapsedExtent,
          minChildSize: _collapsedExtent,
          maxChildSize: kDiscoverySheetFull,
          snap: true,
          snapSizes: [_collapsedExtent, kDiscoverySheetHalf, kDiscoverySheetFull],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppTheme.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            // IMPORTANT: `_SheetHandleBar` must stay a single, always-present
            // widget here — never swapped for a differently-shaped subtree
            // based on `_isCollapsed`. It owns the GestureDetector tracking
            // the in-progress drag; if that Element gets torn down mid-drag
            // (as it would if this were `_isCollapsed ? WidgetA : WidgetB`),
            // Flutter's gesture arena is left resolving a pointer whose
            // recognizer no longer exists — this is what caused the drag to
            // go dead and throw `Bad state: No element` once the extent
            // crossed the collapsed/half threshold mid-gesture. Only the
            // content *below* the bar (search/chips/list) may freely
            // come and go — none of it holds the drag recognizer.
            child: Column(
              children: [
                _SheetHandleBar(
                  collapsed: _isCollapsed,
                  count: filtered.length,
                  onDragUpdate: (d) => _onHandleDragUpdate(d, areaHeight),
                  onDragEnd: _onHandleDragEnd,
                  onTap: _toggleCollapse,
                ),
                if (!_isCollapsed) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _SearchField(
                        controller: _searchCtrl, onChanged: _onSearchChanged),
                  ),
                  CategoryChipsRow(
                    active: _activeCategory,
                    onSelected: (c) => setState(() => _activeCategory = c),
                  ),
                  if (located.fellBack)
                    _FallbackNote(location: location!, matched: located.matched),
                  const SizedBox(height: 4),
                  Expanded(
                    child: filtered.isEmpty
                        ? _EmptyState(
                            hasFilters: hasFilters,
                            onClear: () {
                              _searchCtrl.clear();
                              setState(() {
                                _query = '';
                                _activeCategory = 'all';
                              });
                            },
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => AssetCard(
                              gem: filtered[i],
                              showLocation: located.fellBack,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The sheet's drag handle + title, in ONE widget that stays mounted across
/// both the collapsed and expanded states — only its internal layout changes
/// with [collapsed]. This is deliberate: an earlier version swapped between
/// two entirely different widgets (a collapsed bar vs. a separate handle+title
/// pair) based on collapsed state, which tore down the active GestureDetector
/// mid-drag the instant the extent crossed the collapsed/half threshold —
/// Flutter's gesture arena was left resolving a pointer whose recognizer no
/// longer existed, which is what produced the dead drag and the cascading
/// `Bad state: No element` exceptions. Keeping one stable Element here means
/// Flutter updates it in place instead of unmounting/remounting mid-gesture.
/// [DragTarget]-free — this is sheet-resize drag, not the gem
/// drag-to-itinerary gesture (that's [AssetCard]'s [Draggable]).
class _SheetHandleBar extends StatelessWidget {
  const _SheetHandleBar({
    required this.collapsed,
    required this.count,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  final bool collapsed;
  final int count;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      onTap: onTap,
      child: collapsed ? _collapsedRow() : _expandedRows(),
    );
  }

  // Collapsed: handle pill + "Discover gems · N nearby ⌃" share one compact row.
  Widget _collapsedRow() {
    return SizedBox(
      height: _kCollapsedContentPx,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Text('Discover gems',
                style: TextStyle(
                    color: AppTheme.lightInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Expanded(child: Center(child: _HandlePill())),
            Text('$count nearby',
                style: const TextStyle(
                    color: AppTheme.lightMute,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_up,
                size: 16, color: AppTheme.lightMute),
          ],
        ),
      ),
    );
  }

  // Expanded (half/full): pill on its own row, then "Discover gems · N nearby ⌄".
  Widget _expandedRows() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(child: _HandlePill()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text('Discover gems',
                    style: TextStyle(
                        color: AppTheme.lightInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Text('$count nearby',
                  style: const TextStyle(
                      color: AppTheme.lightMute,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: AppTheme.lightMute),
            ],
          ),
        ),
      ],
    );
  }
}

class _HandlePill extends StatelessWidget {
  const _HandlePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: AppTheme.lightBorder,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.lightInk, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search gems',
        hintStyle: const TextStyle(color: AppTheme.lightMute, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: AppTheme.lightMute, size: 20),
        filled: true,
        fillColor: AppTheme.lightCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

class _FallbackNote extends StatelessWidget {
  const _FallbackNote({required this.location, required this.matched});

  final String location;
  final int matched;

  @override
  Widget build(BuildContext context) {
    final lead = matched == 0
        ? 'No gems tagged $location yet.'
        : matched == 1
            ? 'Only 1 gem tagged $location.'
            : 'Only $matched gems tagged $location.';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, color: AppTheme.lightMute, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$lead Showing all gems below.',
                style: const TextStyle(
                    color: AppTheme.lightMute, fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore, color: AppTheme.lightMute, size: 40),
            const SizedBox(height: 12),
            Text(
              hasFilters ? 'No gems match your filters.' : 'No gems to show yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.lightMute, fontSize: 14),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onClear,
                child: const Text('Clear filters',
                    style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

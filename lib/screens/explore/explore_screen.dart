import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/gem_categories.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gem_provider.dart';
import '../../models/gem.dart';
import 'feed_metrics.dart';
import 'gem_card.dart';
import 'map_engine.dart';
import 'map_loading_overlay.dart';

// Presentational + support classes (small controls, bottom sheet, gem-detail
// sheet, carousel cards, helper value types) live in this part file to keep the
// stateful screen logic above readable. They share this library's imports and
// private scope, so the split is purely physical — no behavior change.
part 'explore_screen_widgets.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

enum _MapStyle { outdoors, dark, satellite }

/// Where a gem selection originated, so the one [_selectGem] codepath knows which
/// side effects to run without duplicating selection flags. Two derived booleans
/// cover every case: scroll the deck (everything except a deck swipe, which is
/// already there) and move the camera (everything except a pin tap, where the
/// user already sees the pin).
enum _SelectSource { deckSwipe, pinTap, listTap }

class _ExploreScreenState extends State<ExploreScreen> {
  MapEngineController? _engine;
  late _MapStyle _style;
  double? _userLat, _userLng;
  String? _city;

  /// One-shot launch gate: true until the FIRST city/area resolve settles. While
  /// set, the loading overlay stays up so the sheet never flashes the global gem
  /// set before an active area lands. Lifted (and never re-armed) on the first
  /// _resolveCity completion or a denied/failed locate.
  bool _areaPending = true;

  /// Latched visibility for the "Search this area" pill. Hysteresis: flips TRUE
  /// once the viewport centre drifts a margin BEYOND the active-area bbox, flips
  /// FALSE only when it returns INSIDE the bbox — so panning near the edge never
  /// strobes it. Tapping the pill is the ONLY thing a pan can trigger that
  /// rescopes the feed; panning alone never changes the area.
  bool _showSearchHere = false;

  // Live map bearing in degrees, fed by the engine's onBearingChanged. Drives
  // the rotation-gated compass: the compass control only appears once the map
  // is rotated off north, then fades away again when reset.
  double _bearing = 0;

  // The sheet's live height from the bottom edge, in logical px — the SINGLE
  // source of truth for map↔sheet sync. The sheet pushes it on every drag frame
  // (via onCoverage); the FAB rides above it (ValueListenableBuilder) and gem
  // focuses offset the camera by it, so map and FAB stay glued to the sheet at
  // every detent through this one value rather than scattered listeners.
  final ValueNotifier<double> _sheetExtentPx = ValueNotifier<double>(0);

  // ── shared selection (single source of truth for deck ⇄ pins) ──
  // One selected-gem id that BOTH the floating deck and the map markers read.
  // The deck's PageController and the engine's pin highlight are OUTPUTS of
  // _selectGem, never independent flags, so the two can never disagree.
  String? _selectedGemId;
  final PageController _deckController =
      PageController(viewportFraction: 1.0);
  // Guards against the programmatic animateToPage in _selectGem re-entering
  // onPageChanged and firing a spurious deckSwipe selection (a feedback loop).
  bool _suppressDeckCallback = false;
  // The deck is the hero only at the peek detent; once the sheet expands into
  // the full list the deck fades out. Pushed by the sheet via onSnap.
  bool _sheetAtPeek = true;

  // Live screen geometry, captured each build, so the imperative overlay-shield
  // push (which can fire off-build from _onSheetCoverage) can compute pixel
  // bands without a BuildContext. _hasGems mirrors `gems.isNotEmpty` so the deck
  // band is only laid when the deck is actually on screen.
  double _screenW = 0, _screenH = 0, _topInset = 0;
  bool _hasGems = false;

  // ── Search modal state ──
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  String _query = '';
  final List<String> _recent = [];
  List<_LocResult> _locResults = [];
  bool _locLoading = false;
  Timer? _searchDebounce;

  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';
  final GeocodingService _geo = GeocodingService();

  // Pick day vs. night based on the device's local clock (reflects the user's
  // time zone). Daytime → outdoors (light); night → dark.
  static bool get _isDaytime {
    final h = DateTime.now().hour;
    return h >= 6 && h < 18;
  }

  static _MapStyle get _autoStyle =>
      _isDaytime ? _MapStyle.outdoors : _MapStyle.dark;

  @override
  void initState() {
    super.initState();
    _style = _autoStyle;
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && !_searchFocused) {
        setState(() => _searchFocused = true);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _sheetExtentPx.dispose();
    _deckController.dispose();
    super.dispose();
  }

  IconData _iconFor(String? cat) => GemCategories.iconFor(cat);

  String get _styleId {
    switch (_style) {
      case _MapStyle.dark:
        return 'dark-v11';
      case _MapStyle.satellite:
        return 'satellite-streets-v12';
      case _MapStyle.outdoors:
        return 'outdoors-v12';
    }
  }

  List<MapMarkerData> _markersFor(List<Gem> gems) => gems
      .map((g) => MapMarkerData(
            id: g.id,
            lat: g.latitude!,
            lng: g.longitude!,
            emoji: g.emoji,
            icon: _iconFor(g.category),
            photoUrl: g.photoUrl,
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    final gemProv = context.watch<GemProvider>();
    final gems = gemProv.mappableGems;
    // The floating deck is clipped to the gems inside the current map viewport
    // (markers stay global), nearest-first from the shared anchor — so it never
    // shows a card for an off-screen pin and the card order matches its pill.
    final deckGems = gemProv.deckGems(userLat: _userLat, userLng: _userLng);
    final deckAnchor = gemProv.deckAnchor(userLat: _userLat, userLng: _userLng);

    // Snapshot the geometry the overlay shields depend on, then (post-frame, so
    // the layout is settled) re-push them. This covers every state-driven change
    // — search focus, peek↔full, gem set, screen resize — in one place; the
    // per-frame deck tracking during a sheet drag is handled in _onSheetCoverage.
    final mq = MediaQuery.of(context);
    _screenW = mq.size.width;
    _screenH = mq.size.height;
    _topInset = mq.padding.top;
    _hasGems = gems.isNotEmpty;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _pushOverlayShields());

    final q = _query.trim().toLowerCase();
    final seenKeys = <String>{};
    final matchedGems = q.length >= 2
        ? gemProv.allGems
            .where((g) =>
                g.gemName.toLowerCase().contains(q) ||
                (g.category?.toLowerCase().contains(q) ?? false) ||
                (g.gemLocation?.toLowerCase().contains(q) ?? false))
            // Collapse duplicate listings (same name + place) so one spot can't
            // appear five times; genuinely distinct gems are kept.
            .where((g) => seenKeys.add(
                '${g.gemName.toLowerCase()}|${(g.gemLocation ?? '').toLowerCase()}'))
            .take(6)
            .toList()
        : <Gem>[];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── MAP (Mapbox GL globe on web; flutter_map fallback on native) ──
          MapEngineView(
            markers: _markersFor(gems),
            styleId: _styleId,
            token: _token,
            userLat: _userLat,
            userLng: _userLng,
            // Tapping a pin SELECTS its gem (scrolls the deck to it + highlights
            // the pin) rather than opening the detail outright — the deck is the
            // browse surface now. Detail opens by tapping the deck card.
            onMarkerTap: (id) => _selectGem(id, _SelectSource.pinTap),
            // Camera settled → store the viewport bounds so the deck re-clips to
            // the gems now on screen (centre is ignored here; the deck derives
            // its anchor from the bounds when location is unknown).
            onCameraIdle: _onCameraIdle,
            // Track the live bearing so the compass control can reveal itself
            // only when the map is actually rotated off north.
            onBearingChanged: (b) {
              // Treat sub-degree wobble as north so the compass doesn't flicker.
              final rotated = b.abs() > 1.0;
              final wasRotated = _bearing.abs() > 1.0;
              if (rotated != wasRotated || (rotated && b != _bearing)) {
                setState(() => _bearing = b);
              }
            },
            onReady: (c) {
              _engine = c;
              // Re-apply the current sheet coverage: the engine may mount after
              // the sheet has already reported its first pixel extent.
              c.setSheetCoverage(_sheetExtentPx.value);
              // Lay the overlay shields too: the engine may mount after the
              // chips/deck have already laid out, so re-push their bands now.
              _pushOverlayShields();
              // On open, centre on the user's current location. Falls back to
              // fitting all gem markers if permission is denied/unavailable.
              _locateMe();
            },
          ),

          // ── RIGHT CONTROL CLUSTER (top-right, below the filter chips) ──
          // Trimmed to the three controls that matter at a glance: locate me,
          // the day/night style toggle, and the layers picker. The rotation-
          // gated compass sits ABOVE the pill and only materialises once the
          // map is actually turned off north, then fades away on reset. Zoom
          // ± (pinch/scroll already cover it) and the tools sub-menu were
          // retired so the rail stays a short, legible pill.
          Positioned(
            top: MediaQuery.of(context).padding.top + 124,
            right: 16,
            child: PointerInterceptor(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: _bearing.abs() > 1.0
                        ? Padding(
                            key: const ValueKey('compass'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MapControl(
                              child: _IconHit(
                                icon: Icons.explore,
                                color: AppTheme.primary,
                                onTap: () => _engine?.resetNorth(),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-compass')),
                  ),
                  _MapControl(
                    child: Column(
                      children: [
                        _IconHit(
                          icon: Icons.my_location,
                          color: AppTheme.primary,
                          onTap: _locateMe,
                        ),
                        _ctrlDivider(),
                        _IconHit(
                          icon: _style == _MapStyle.dark
                              ? Icons.wb_sunny_outlined
                              : Icons.dark_mode_outlined,
                          color: const Color(0xFF4FC3F7),
                          onTap: () => setState(() => _style =
                              _style == _MapStyle.dark
                                  ? _MapStyle.outdoors
                                  : _MapStyle.dark),
                        ),
                        _ctrlDivider(),
                        _IconHit(
                          icon: Icons.layers_outlined,
                          onTap: () => _showLayers(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── DROP A GEM (labelled pill) ──
          // Always visible, never occluded: rides above the floating deck when
          // the deck shows (peek + gems present), otherwise just above the thin
          // sheet. Bottom-anchored on the shared _sheetExtentPx so it tracks the
          // sheet at every detent.
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtentPx,
            builder: (context, extentPx, child) {
              final deckShowing = _sheetAtPeek && deckGems.isNotEmpty;
              final lift = deckShowing
                  ? kDeckGapAboveSheet +
                      GemCard.deckHeight +
                      22 +
                      kDropGapAboveDeck
                  : kFabGapAboveSheet;
              return Positioned(
                right: 16,
                bottom: extentPx + lift,
                child: child!,
              );
            },
            child: PointerInterceptor(
              child: GestureDetector(
                onTap: () => context.go('/drop-gem'),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Drop a gem',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── FLOATING CARD DECK (primary browse surface) ──
          // Shown ONLY at the peek detent and ONLY when there are gems IN THE
          // VIEWPORT (empty → just the map, never an empty card). Rides above the
          // sheet's top edge on the shared _sheetExtentPx, exactly like the FAB.
          // Its gem set is `deckGems` — `mappableGems` clipped to the current map
          // bounds, nearest-first — so the deck is a subset of the visible pins:
          // no card ever appears for a gem the user can't see as a marker.
          if (_sheetAtPeek && deckGems.isNotEmpty)
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtentPx,
              builder: (context, extentPx, child) => Positioned(
                left: 0,
                right: 0,
                bottom: extentPx + kDeckGapAboveSheet,
                child: child!,
              ),
              child: PointerInterceptor(
                child: _GemDeck(
                  gems: deckGems,
                  controller: _deckController,
                  gemProv: gemProv,
                  iconFor: _iconFor,
                  selectedId: _selectedGemId,
                  anchorLat: deckAnchor?.$1,
                  anchorLng: deckAnchor?.$2,
                  onCardTap: _showGemSheet,
                  onSwipe: (id) {
                    if (_suppressDeckCallback) return;
                    _selectGem(id, _SelectSource.deckSwipe);
                  },
                ),
              ),
            ),

          // ── "SEARCH THIS AREA" PILL ──
          // Top-centre, below the chip row. Appears (latched, with hysteresis)
          // only once the user has panned the viewport centre clear of the active
          // area; tapping it re-derives the area from the new centre. Panning
          // never rescopes the feed on its own — this is the opt-in.
          if (_showSearchHere)
            Positioned(
              top: chipBandTop(_topInset) + kFilterChipBarHeight + 10,
              left: 0,
              right: 0,
              child: Center(
                child: PointerInterceptor(
                  child: GestureDetector(
                    onTap: _searchThisArea,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.divider),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search,
                              size: 18, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Search this area',
                            style: GoogleFonts.dmSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── BOTTOM SHEET (now the full-list surface) ──
          _BottomSheet(
            gemProv: gemProv,
            iconFor: _iconFor,
            onGemSelected: (id) => _selectGem(id, _SelectSource.listTap),
            onSnap: (snap) {
              if (_sheetAtPeek != snap.isPeek) {
                setState(() => _sheetAtPeek = snap.isPeek);
              }
            },
            onSort: _showSortSheet,
            city: _city,
            userLat: _userLat,
            userLng: _userLng,
            onCoverage: _onSheetCoverage,
            // Reserve the chip-row band (derived ONCE via chipBandTop, the same
            // geometry the gesture shield uses) plus the fixed gap, so the
            // expanded sheet always stops clear of the floating chips.
            topReservedPx: chipBandTop(_topInset) +
                kFilterChipBarHeight +
                kSheetTopGapBelowChips,
          ),

          // ── LOADING / ERROR OVERLAY ──
          // Full-screen "preparing the map" state, driven purely by the
          // provider's async status (no timer, no minimum duration). The
          // AnimatedSwitcher cross-fades the live map in the moment the fetch
          // future completes; on error it holds a brief retry state instead of
          // spinning forever.
          Positioned.fill(
            child: IgnorePointer(
              // Let map gestures through once the overlay is gone; absorb them
              // (over the full-screen overlay) only while it's showing. The
              // launch gate (_areaPending) keeps it up until the first area
              // resolves, so the sheet never flashes the global set.
              ignoring: !(gemProv.loading || gemProv.hasError || _areaPending),
              child: AnimatedSwitcher(
                duration: kMapLoadFade,
                child: (gemProv.loading || gemProv.hasError || _areaPending)
                    ? MapLoadingOverlay(
                        key: ValueKey(gemProv.hasError ? 'error' : 'loading'),
                        userLat: _userLat,
                        userLng: _userLng,
                        isError: gemProv.hasError,
                        onRetry: gemProv.refresh,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // ── SEARCH FOCUS DIM ── (taps anywhere off the panel dismiss search)
          if (_searchFocused)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeSearch,
                behavior: HitTestBehavior.opaque,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 220),
                  builder: (_, t, __) => Container(
                    color: Colors.black.withValues(alpha: 0.38 * t),
                  ),
                ),
              ),
            ),

          // ── TOP: menu + search (+ floating results panel) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, kSearchBarTopPad, 16, 0),
              child: Column(
                children: [
                  _buildSearchField(),
                  // Filter chips ride DIRECTLY under the search bar (moved out
                  // of the sheet). Hidden while the search panel is open so the
                  // two never stack/overlap. PointerInterceptor absorbs taps
                  // before they reach the Mapbox canvas underneath.
                  if (!_searchFocused)
                    Padding(
                      padding: const EdgeInsets.only(top: kChipsTopGap),
                      child: PointerInterceptor(
                        child: _FilterChipsBar(
                          gemProv: gemProv,
                          iconFor: _iconFor,
                        ),
                      ),
                    ),
                  if (_searchFocused)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildSearchPanel(matchedGems),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────── search modal ─────────

  Widget _buildSearchField() {
    return Container(
      height: kSearchBarHeight,
      padding: const EdgeInsets.only(left: 6, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Leading circular "Map Filter" control — opens the map layer picker.
          GestureDetector(
            onTap: () => _showLayers(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tune_rounded,
                  color: AppTheme.primary, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            // Local selection/cursor theme so the caret + selection stay visible
            // on the white pill (the app-wide dark theme would otherwise tint
            // them for a dark surface).
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: AppTheme.primary,
                  selectionColor: AppTheme.primary.withValues(alpha: 0.25),
                  selectionHandleColor: AppTheme.primary,
                ),
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onQueryChanged,
                onTap: () {
                  if (!_searchFocused) setState(() => _searchFocused = true);
                },
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _addRecent(v.trim());
                },
                textInputAction: TextInputAction.search,
                cursorColor: AppTheme.primary,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  color: AppTheme.sheetInk,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  // The app-wide inputDecorationTheme is `filled` with a DARK
                  // surface; force it off here so typed ink shows on the white
                  // pill instead of dark-on-dark (the original bug).
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search gems, cities, vibes…',
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: AppTheme.sheetSubInk,
                  ),
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: _clearQuery,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.close_rounded, color: Color(0xFF8A8A8A), size: 20),
              ),
            ),
          // Embedded microphone — voice search entry point.
          GestureDetector(
            onTap: _startVoiceSearch,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: const Icon(Icons.mic_none_rounded,
                  color: Color(0xFF8A8A8A), size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // Voice search entry point. Real speech-to-text needs the `speech_to_text`
  // plugin plus a microphone-permission flow, which is a separate product
  // decision; until that lands, surface a clear, honest placeholder rather than
  // a dead button.
  void _startVoiceSearch() {
    if (!_searchFocused) setState(() => _searchFocused = true);
    _searchFocus.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Voice search is coming soon — type to search for now.',
          style: GoogleFonts.dmSans(fontSize: 13.5),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSearchPanel(List<Gem> matchedGems) {
    final q = _query.trim();
    final showRecent = q.length < 2 && _recent.isNotEmpty;
    final showResults = q.length >= 2;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -14),
            child: child,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (showRecent) ...[
                    _panelHeader('RECENT SEARCHES'),
                    ..._recent.take(5).map(_recentRow),
                  ],
                  if (showResults) ...[
                    _panelHeader('SUGGESTED GEMS'),
                    if (matchedGems.isEmpty)
                      _panelMessage('No gems match “$q”')
                    else
                      ...matchedGems.map(_gemResultRow),
                    _panelHeader('LOCATIONS'),
                    if (_locLoading)
                      _panelLoading()
                    else if (_locResults.isEmpty)
                      _panelMessage('No places found')
                    else
                      ..._locResults.map(_locResultRow),
                  ],
                  if (!showRecent && !showResults)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Text(
                        'Start typing to find hidden gems, cities and vibes…',
                        style: GoogleFonts.dmSans(
                          fontSize: 13.5,
                          color: const Color(0xFF8A8A8A),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(
          text,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF9A9A9A),
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _panelMessage(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Text(
          text,
          style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF8A8A8A)),
        ),
      );

  Widget _panelLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
          ),
        ),
      );

  Widget _resultIcon(IconData icon, Color color) => Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 18, color: color),
      );

  Widget _recentRow(String term) => InkWell(
        onTap: () => _selectRecent(term),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              _resultIcon(Icons.history, const Color(0xFF8A8A8A)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF222222),
                  ),
                ),
              ),
              const Icon(Icons.north_west, size: 16, color: Color(0xFFBBBBBB)),
            ],
          ),
        ),
      );

  Widget _gemResultRow(Gem g) => InkWell(
        onTap: () => _selectSearchGem(g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              _resultIcon(_iconFor(g.category), AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.gemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111111),
                      ),
                    ),
                    if (g.gemLocation != null && g.gemLocation!.isNotEmpty)
                      Text(
                        g.gemLocation!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF8A8A8A),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  g.displayCategory.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _locResultRow(_LocResult r) {
    var secondary = r.context;
    if (secondary.toLowerCase().startsWith('${r.name.toLowerCase()}, ')) {
      secondary = secondary.substring(r.name.length + 2);
    }
    return InkWell(
      onTap: () => _selectLocation(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            _resultIcon(Icons.place_outlined, const Color(0xFF12A594)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111111),
                    ),
                  ),
                  if (secondary.isNotEmpty)
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: const Color(0xFF8A8A8A),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_outward, size: 16, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    if (v.trim().length >= 2) {
      _searchDebounce =
          Timer(const Duration(milliseconds: 320), () => _searchLocations(v.trim()));
    } else {
      setState(() {
        _locResults = [];
        _locLoading = false;
      });
    }
  }

  void _clearQuery() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _locResults = [];
      _locLoading = false;
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    setState(() {
      _searchFocused = false;
      _query = '';
      _locResults = [];
      _locLoading = false;
    });
  }

  void _addRecent(String term) {
    setState(() {
      _recent.removeWhere((e) => e.toLowerCase() == term.toLowerCase());
      _recent.insert(0, term);
      if (_recent.length > 5) _recent.removeRange(5, _recent.length);
    });
  }

  void _selectRecent(String term) {
    _searchCtrl.text = term;
    _searchCtrl.selection = TextSelection.collapsed(offset: term.length);
    _onQueryChanged(term);
  }

  void _selectSearchGem(Gem g) {
    _addRecent(g.gemName);
    _onResultSelected(lat: g.latitude, lng: g.longitude, gem: g);
  }

  void _selectLocation(_LocResult r) {
    debugPrint('[flyto] 1 tap LOCATION name=${r.name} lat=${r.lat} lng=${r.lng}');
    _addRecent(r.name);
    _onResultSelected(
        lat: r.lat, lng: r.lng, locationLabel: r.name, locationBbox: r.bbox);
  }

  /// The single "fly-to-result" path. Every search result — suggested gem or
  /// location, and any future type — recenters the map through here, so there's
  /// one camera codepath instead of per-type copies.
  ///
  /// * GEM → sheet-aware [MapEngineController.focusGem] (clears the bottom
  ///   sheet) + the detail sheet. The detail still opens for a gem with no
  ///   coords (there's just nothing to fly to).
  /// * LOCATION → [MapEngineController.flyTo] at city zoom, titles the sheet
  ///   with the place, and narrows the feed to that area so the count stops
  ///   asserting far-away spots. A location with no centre is a no-op that
  ///   leaves the overlay open rather than a dead tap.
  void _onResultSelected({
    double? lat,
    double? lng,
    Gem? gem,
    String? locationLabel,
    List<double>? locationBbox,
  }) {
    if (gem != null) {
      _closeSearch();
      _showGemSheet(gem); // focuses if it has coords, always shows the detail
      return;
    }
    if (lat == null || lng == null) return; // no target → keep overlay open
    // Reject out-of-range coordinates so a malformed result can never move the
    // camera to an invalid latitude/longitude and black out the map.
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      debugPrint('Ignoring out-of-range result coord: lat=$lat lng=$lng');
      return;
    }
    _closeSearch();
    // Scope the sheet to the searched area FIRST, then animate the camera AFTER
    // this frame settles. The flyTo is deferred past the overlay-close + the
    // focus rebuild so the long globe arc isn't interrupted mid-flight and left
    // resting at its zoomed-out apex (the "flies to a whole continent" bug).
    setState(() => _city = locationLabel ?? _city);
    // Scope the sheet to the place's bbox (the whole city/region), not a radius.
    _applySearchArea(lat, lng, locationBbox, locationLabel);
    debugPrint('[flyto] 2 scheduling postFrame engine=${_engine != null} '
        'target=$lat,$lng z=12');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[flyto] 3 postFrame fired engine=${_engine != null} '
          'target=$lat,$lng');
      _engine?.flyTo(lat, lng, 12);
    });
  }

  /// Fixed degree padding for the NON-bbox fallback ONLY (≈15 km half-span) —
  /// used when a result and its enclosing city both lack a bbox, so we still get
  /// a city-sized window instead of the old radius dot. Never the primary path.
  static const double _kFallbackPadDeg = 0.15;

  /// Scopes the sheet active area to a searched result. Primary path: the
  /// place's own [bbox]. Fallback for point-like results (POI/address) with no
  /// bbox: borrow the enclosing city's bbox via one reverse-geocode; only if
  /// that too is missing do we synthesize a fixed-padding box around the point.
  Future<void> _applySearchArea(
      double lat, double lng, List<double>? bbox, String? label) async {
    final prov = context.read<GemProvider>();
    if (bbox != null) {
      prov.setActiveArea(bbox[0], bbox[1], bbox[2], bbox[3], label: label);
      return;
    }
    final parent = await _geo.reverse(lat, lng, types: 'place');
    if (!mounted) return;
    final pb = parent?.bbox;
    if (pb != null) {
      context
          .read<GemProvider>()
          .setActiveArea(pb[0], pb[1], pb[2], pb[3], label: label ?? parent?.name);
      return;
    }
    const pad = _kFallbackPadDeg; // non-bbox fallback ONLY
    context.read<GemProvider>().setActiveArea(
        lng - pad, lat - pad, lng + pad, lat + pad,
        label: label);
  }

  // Forward-geocode the query into city / neighbourhood matches via Mapbox.
  Future<void> _searchLocations(String q) async {
    if (q.length < 2) {
      if (mounted) setState(() => _locResults = []);
      return;
    }
    if (mounted) setState(() => _locLoading = true);
    final places = await _geo.search(q);
    final results = places
        .map((p) => _LocResult(
              name: p.name,
              context: p.fullName,
              lng: p.lng,
              lat: p.lat,
              bbox: p.bbox,
            ))
        .toList();
    if (!mounted) return;
    // Ignore stale responses if the query has since changed.
    if (q == _query.trim()) {
      setState(() {
        _locResults = results;
        _locLoading = false;
      });
    } else {
      setState(() => _locLoading = false);
    }
  }

  // ───────── helpers ─────────

  // Tapping a marker (or a carousel card) flies the camera to the gem and
  // slides a full detail sheet up from the bottom.
  /// The single selection codepath. Sets the shared [_selectedGemId] that both
  /// the deck and the markers read, then fans out the side effects:
  ///  • highlight the pin (+ dim the rest) via the engine,
  ///  • scroll the deck to the card — unless the swipe itself originated it,
  ///  • move the camera so the pin clears the deck — unless it was a pin tap
  ///    (the user already sees that pin).
  void _selectGem(String id, _SelectSource source) {
    final gemProv = context.read<GemProvider>();
    final gems = gemProv.mappableGems;
    final index = gems.indexWhere((g) => g.id == id);
    if (index < 0) return;
    final gem = gems[index];

    if (_selectedGemId != id) setState(() => _selectedGemId = id);
    _engine?.select(id);

    // Scroll the deck by the gem's index in the DECK's own (viewport-clipped)
    // list, not in the global mappable list — the two differ now. If the gem
    // isn't in the viewport it's simply not a deck card, so skip the scroll.
    final deckGems = gemProv.deckGems(userLat: _userLat, userLng: _userLng);
    final deckIndex = deckGems.indexWhere((g) => g.id == id);
    if (source != _SelectSource.deckSwipe &&
        deckIndex >= 0 &&
        _deckController.hasClients) {
      _suppressDeckCallback = true;
      _deckController
          .animateToPage(deckIndex,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic)
          .whenComplete(() => _suppressDeckCallback = false);
    }

    if (source != _SelectSource.pinTap && gem.hasCoords) {
      _engine?.focusGem(
          gem.latitude!, gem.longitude!, 13, _sheetExtentPx.value);
    }
  }

  void _showGemSheet(Gem gem) {
    if (gem.hasCoords) {
      _engine?.focusGem(
          gem.latitude!, gem.longitude!, 13, _sheetExtentPx.value);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GemDetailSheet(
        gem: gem,
        icon: _iconFor(gem.category),
        userLat: _userLat,
        userLng: _userLng,
      ),
    );
  }

  // Sort picker for the feed's top-right button. Light sheet to match the feed.
  void _showSortSheet() {
    final prov = context.read<GemProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.sheetHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final s in GemSort.values)
              ListTile(
                leading: Icon(
                  s == GemSort.recent ? Icons.schedule : Icons.sort_by_alpha,
                  color: prov.sort == s
                      ? AppTheme.primary
                      : const Color(0xFF8A8A8A),
                ),
                title: Text(
                  s == GemSort.recent ? 'Most recent' : 'Name (A–Z)',
                  style: GoogleFonts.dmSans(
                    color: prov.sort == s
                        ? AppTheme.primary
                        : const Color(0xFF111111),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: prov.sort == s
                    ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                    : null,
                onTap: () {
                  prov.setSort(s);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _ctrlDivider() =>
      Container(width: 26, height: 1, color: AppTheme.divider);

  // The bottom sheet reports how many pixels of the map it currently covers.
  // Cache it (so a late-mounting engine can be re-synced in onReady) and forward
  // it to the web engine, which lays a transparent gesture shield over that strip
  // to stop sheet drags/scrolls bleeding into the Mapbox canvas underneath.
  void _onSheetCoverage(double px) {
    // One value, fanned out to every consumer: the FAB (listens to the
    // notifier), gem focuses (read it at tap time), and the web gesture shield.
    _sheetExtentPx.value = px;
    _engine?.setSheetCoverage(px);
    // The deck rides on the sheet's top edge, so its shield band moves with the
    // sheet on every drag frame. Re-push here (this runs off-build, so the
    // notifier alone wouldn't re-lay the band).
    _pushOverlayShields();
  }

  // Lays transparent DOM gesture shields over the floating overlays that sit
  // ABOVE the map — the filter-chip row (under the search bar) and the card deck
  // (above the sheet) — so horizontal swipes on them are absorbed before they
  // reach the Mapbox canvas and pan the globe. Mirrors the bottom-sheet shield
  // (setSheetCoverage); no-op on native. Bands are in CSS px from the map's
  // top-left, which equals Flutter logical px on web.
  void _pushOverlayShields() {
    final engine = _engine;
    if (engine == null) return;
    final rects = <MapShieldRect>[];
    // Chip band: directly under the search field (SafeArea top + 12 pad + 52
    // field + 10 gap = top+74), full content width (16px gutters), 44 tall.
    if (!_searchFocused) {
      final w = _screenW - 32;
      if (w > 0) {
        rects.add(MapShieldRect(
          top: chipBandTop(_topInset),
          left: 16,
          width: w,
          height: kFilterChipBarHeight,
        ));
      }
    }
    // Deck band: full-width, sitting on the sheet's top edge. Same height the
    // deck reserves (GemCard.deckHeight + 22), lifted by the live sheet extent
    // plus the deck↔sheet gap — identical math to the deck's own Positioned.
    if (_sheetAtPeek && _hasGems) {
      const deckH = GemCard.deckHeight + 22;
      final top = _screenH - (_sheetExtentPx.value + kDeckGapAboveSheet + deckH);
      rects.add(MapShieldRect(
        top: top,
        left: 0,
        width: _screenW,
        height: deckH,
      ));
    }
    engine.setOverlayShields(rects);
  }

  Future<void> _locateMe() async {
    // Locate = "show my city's gems": it flies to the user AND re-resolves the
    // active area to that city (via _resolveCity below). We deliberately DON'T
    // blank the area to global here — the prior area holds until the new city
    // resolves, so the sheet never flashes the whole-map set mid-locate.
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          _engine?.fitMarkers(
              _markersFor(context.read<GemProvider>().mappableGems));
          // No location → no city to resolve; lift the launch gate so the sheet
          // shows (it falls back to the global feed, the conscious choice).
          setState(() => _areaPending = false);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
      }
      _engine?.flyTo(pos.latitude, pos.longitude, 13);
      _resolveCity(pos.latitude, pos.longitude);
    } catch (_) {
      if (mounted) {
        _engine?.fitMarkers(
            _markersFor(context.read<GemProvider>().mappableGems));
        // Location lookup failed → lift the launch gate so the sheet isn't
        // stuck behind the loading overlay forever.
        setState(() => _areaPending = false);
      }
    }
  }

  /// Margin (degrees) the viewport centre must clear BEYOND the active-area bbox
  /// before the "Search this area" pill appears. Paired with an inside-the-bbox
  /// hide test, it gives the latch hysteresis so it doesn't strobe at the edge.
  static const double _kAreaShowMarginDeg = 0.05;

  /// Camera settled: store the viewport bounds (re-clips the deck) and re-run the
  /// hysteresis that latches the "Search this area" pill. Centre is (lat,lng).
  void _onCameraIdle(
      double lat, double lng, double w, double s, double e, double n) {
    final prov = context.read<GemProvider>();
    prov.setViewport(w, s, e, n);
    final area = prov.activeAreaBounds;
    if (area == null) {
      if (_showSearchHere) setState(() => _showSearchHere = false);
      return;
    }
    final (aW, aS, aE, aN) = area;
    const m = _kAreaShowMarginDeg;
    // Beyond the bbox by the margin → offer the re-search. Back inside the bbox
    // proper → hide. Between the two thresholds the latch holds its last value.
    // assumes non-wrapping bounds (W < E)
    final beyond =
        lng < aW - m || lng > aE + m || lat < aS - m || lat > aN + m;
    final inside = lng >= aW && lng <= aE && lat >= aS && lat <= aN;
    var next = _showSearchHere;
    if (beyond) {
      next = true;
    } else if (inside) {
      next = false;
    }
    if (next != _showSearchHere) setState(() => _showSearchHere = next);
  }

  /// Re-derives the active area from the CURRENT viewport centre on demand (the
  /// "Search this area" pill). This is the only pan-aware rescope — panning by
  /// itself never moves the area. Reverse-geocodes the centre to a city bbox.
  Future<void> _searchThisArea() async {
    final prov = context.read<GemProvider>();
    final c = prov.viewportCenter;
    if (c == null) return;
    setState(() => _showSearchHere = false);
    final place = await _geo.reverse(c.$1, c.$2);
    if (!mounted) return;
    final bbox = place?.bbox;
    if (bbox != null) {
      prov.setActiveArea(bbox[0], bbox[1], bbox[2], bbox[3], label: place?.name);
      final name = place?.name;
      if (name != null && name.isNotEmpty) setState(() => _city = name);
    }
  }

  // Reverse-geocode the user's coordinate to a city/place name via Mapbox so
  // the bottom sheet can title itself with where the explorer actually is.
  Future<void> _resolveCity(double lat, double lng) async {
    final place = await _geo.reverse(lat, lng);
    if (!mounted) return;
    final name = place?.name;
    final bbox = place?.bbox;
    // Scope the sheet to the resolved city's bbox (so the list + counts cover
    // the whole city, not the globe). A city with no bbox leaves the area unset
    // → the feed spans every gem, the conscious fallback.
    if (bbox != null) {
      context.read<GemProvider>().setActiveArea(
          bbox[0], bbox[1], bbox[2], bbox[3],
          label: name);
    }
    setState(() {
      if (name != null && name.isNotEmpty) _city = name;
      // One-shot: the launch gate lifts once the FIRST resolve settles (success
      // or not), so the sheet never flashes the global set before an area lands.
      _areaPending = false;
    });
  }

  void _showLayers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final s in _MapStyle.values)
              ListTile(
                leading: Icon(
                  s == _MapStyle.outdoors
                      ? Icons.terrain
                      : s == _MapStyle.dark
                          ? Icons.dark_mode
                          : Icons.satellite_alt,
                  color: _style == s ? AppTheme.primary : AppTheme.textSecondary,
                ),
                title: Text(
                  s == _MapStyle.outdoors
                      ? 'Outdoors'
                      : s == _MapStyle.dark
                          ? 'Dark'
                          : 'Satellite',
                  style: GoogleFonts.dmSans(
                    color: _style == s ? AppTheme.primary : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: _style == s
                    ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                    : null,
                onTap: () {
                  setState(() => _style = s);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/mapbox_tilequery_service.dart';
import '../../core/services/poi_category_filter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attraction.dart';
import '../../models/gem.dart';
import '../../models/restaurant.dart';
import '../../models/trip.dart';
import '../../models/trip_stop.dart';
import '../../providers/gem_provider.dart';
import '../../providers/trip_provider.dart';
import '../../repositories/attraction_repository.dart';
import '../../repositories/restaurant_repository.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/auth/sign_in_sheet.dart';
import '../../widgets/common/photo_carousel.dart';
import '../../widgets/gems/linked_business_card.dart';
import '../explore/feed_metrics.dart';
import '../explore/map_engine.dart';

/// Which collapsible section is open — single-open accordion, so this is a
/// single value rather than a Set. Null means nothing is open (every section
/// was hidden for lack of data, or the user collapsed the only open one).
enum _Section { about, goodToKnow, location }

/// Whether [gem] already has a stop on [stops] — used to block the sticky
/// CTA from creating a duplicate stop on a double-tap (TripProvider.addStop
/// has no dedup of its own, confirmed by reading it directly: no gemId/
/// tripId uniqueness check, and no unique constraint on trip_stops either).
/// Only meaningful for a real, non-POI gem: a POI-derived stop is created
/// via customPayload (see _addToTrip) rather than gemId, which carries no
/// stable identifier to dedupe against — see this function's call site for
/// that scoping. Top-level and public (not a private State method) so it's
/// unit-testable without building the widget tree, same convention as
/// feed_metrics.dart's gemDistanceLabel.
bool gemAlreadyOnTrip(Gem gem, List<TripStop> stops) =>
    stops.any((s) => s.gemId == gem.id);

/// Attempts to launch [uri] via [launcher] (real url_launcher.launchUrl by
/// default, overridable for tests) and returns whether it succeeded. A
/// platform-level failure (no maps app installed, launch blocked, ...) is
/// caught and treated the same as the launcher returning false — this never
/// throws, so callers can rely on the boolean alone rather than needing
/// their own try/catch. Top-level and public for the same testability
/// reason as [gemAlreadyOnTrip].
Future<bool> attemptExternalLaunch(
  Uri uri, {
  Future<bool> Function(Uri uri, {LaunchMode mode}) launcher = launchUrl,
}) async {
  try {
    return await launcher(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class GemDetailScreen extends StatefulWidget {
  /// A real saved_gems row id — fetched from GemProvider/the DB. Mutually
  /// exclusive with [poi].
  final String? id;

  /// A Mapbox-sourced point of interest (e.g. tapped from a destination
  /// landing page's "Top things to do" card) — rendered directly, no DB
  /// fetch at all, since it has no saved_gems row. Mutually exclusive with
  /// [id].
  final NearbyPoi? poi;

  const GemDetailScreen({super.key, required this.id}) : poi = null;
  const GemDetailScreen.fromPoi({super.key, required this.poi}) : id = null;

  @override
  State<GemDetailScreen> createState() => _GemDetailScreenState();
}

class _GemDetailScreenState extends State<GemDetailScreen> {
  Gem? _gem;
  List<NearbyPoi> _nearby = [];
  bool _loading = true;

  /// A verified business listing linked to this Gem, if one exists — see
  /// the class doc note added below and
  /// docs/audits/attraction-business-profile-2026-09-04.md for the full
  /// decision. Null (the common case, at least until businesses start
  /// claiming places) just means no business has verified this place —
  /// never an error, and the existing curated content above is never
  /// affected by its presence or absence. A Gem can have at most one
  /// linked listing PER business type (an Attraction AND a Restaurant
  /// could both legitimately link to the same real place — e.g. a
  /// heritage site with an on-site restaurant), so this and
  /// [_linkedRestaurant] are independent, both nullable.
  Attraction? _linkedAttraction;
  Restaurant? _linkedRestaurant;

  // Straight-line distance to the gem — best-effort location, same
  // permission-check/request/fallback shape used elsewhere in this app
  // (ListingsScreen._loadNearby, HomeScreen's _NearbyGems, ...) — there's no
  // shared helper for it yet (a known, separately-tracked gap; see
  // listings_screen.dart's identical comment), so this repeats the pattern
  // rather than half-wiring a new one here. Fetched in parallel with _load,
  // never blocks the loading spinner — a missing location just means the
  // distance line/section text doesn't render.
  Position? _userPos;

  _Section? _openSection;

  final MapboxTilequeryService _tilequery = MapboxTilequeryService();

  @override
  void initState() {
    super.initState();
    _load();
    _loadUserLocation();
  }

  /// Builds a transient, never-persisted Gem straight from a Mapbox POI —
  /// no DB fetch, since Mapbox places don't have a saved_gems row. Leaves
  /// every field the app has no real data for (description, tagline,
  /// difficulty, bestTimeToVisit, photos) null/empty rather than fabricating
  /// content — the UI already hides each of those sections when absent.
  Gem _gemFromPoi(NearbyPoi poi) => Gem(
        id: 'poi:${poi.lat},${poi.lng}',
        gemName: poi.name,
        category: poi.category,
        latitude: poi.lat,
        longitude: poi.lng,
        savedAt: DateTime.now(),
        maki: poi.maki,
        isFromPoi: true,
      );

  Future<void> _load() async {
    Gem? gem;
    if (widget.poi != null) {
      gem = _gemFromPoi(widget.poi!);
    } else {
      final prov = context.read<GemProvider>();
      // Confirmed safe: GemRepository.fetchGems selects '*' (every column,
      // not a lightweight list-view projection), so a cache hit here is a
      // full record — description/bestTimeToVisit/goodToKnow/etc. are never
      // missing just because this gem was already loaded into allGems.
      final cached = prov.allGems.where((g) => g.id == widget.id).firstOrNull;
      gem = cached ?? await prov.fetchById(widget.id!);
    }
    if (gem == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Captured into a final local so it stays promoted to non-null inside
    // the setState closure below — `gem` itself is a mutable local and
    // doesn't survive that promotion across a closure boundary.
    final resolvedGem = gem;
    List<NearbyPoi> nearby = const [];
    if (resolvedGem.hasCoords) {
      nearby = await _tilequery.nearby(
          resolvedGem.latitude!, resolvedGem.longitude!,
          radiusMeters: 800, limit: 50);
      // Tilequery has no notion of "this exact place" to exclude — drop
      // anything suspiciously close (< 15m) so the gem itself doesn't show
      // up in its own "Nearby Experiences" rail.
      nearby = nearby.where((p) => (p.distanceMeters ?? 999) > 15).toList();
      // Same allowlist Destination Detail and Listings apply — this rail
      // presents POIs as travel-worthy "experiences," so government
      // offices/parking/etc. don't belong here either.
      nearby = filterTravelRelevantPois(nearby);
    }
    // A POI-derived gem has no saved_gems row, so it can't have a linked
    // Attraction/Restaurant either (gem_id references saved_gems
    // specifically). Fetched in parallel — independent lookups, neither
    // depends on the other's result.
    Attraction? linkedAttraction;
    Restaurant? linkedRestaurant;
    if (!resolvedGem.isFromPoi) {
      final results = await Future.wait([
        AttractionRepository().fetchVerifiedForGem(resolvedGem.id),
        RestaurantRepository().fetchVerifiedForGem(resolvedGem.id),
      ]);
      linkedAttraction = results[0] as Attraction?;
      linkedRestaurant = results[1] as Restaurant?;
    }
    if (mounted) {
      setState(() {
        _gem = resolvedGem;
        _nearby = nearby;
        _linkedAttraction = linkedAttraction;
        _linkedRestaurant = linkedRestaurant;
        _loading = false;
        _openSection = _defaultSection(resolvedGem);
      });
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPos = pos);
    } catch (_) {
      // Keep _userPos null — the distance line/section text just don't
      // render, same "omit rather than fabricate" rule as every other
      // optional field on this screen.
    }
  }

  bool _hasAbout(Gem gem) =>
      (gem.description?.isNotEmpty ?? false) ||
      (gem.bestTimeToVisit?.isNotEmpty ?? false) ||
      (gem.difficulty?.isNotEmpty ?? false);

  bool _hasLocation(Gem gem) =>
      gem.hasCoords || (gem.gemLocation?.isNotEmpty ?? false);

  /// About first (matches the spec's "open by default"), falling through to
  /// whichever section actually has content for a sparser gem/POI — never
  /// defaults open on a section that's about to render as hidden.
  _Section? _defaultSection(Gem gem) {
    if (_hasAbout(gem)) return _Section.about;
    if (gem.goodToKnow.isNotEmpty) return _Section.goodToKnow;
    if (_hasLocation(gem)) return _Section.location;
    return null;
  }

  // Tapping the open section again closes it fully (possibly leaving
  // nothing expanded) rather than forcing one section to always stay open —
  // standard accordion behavior. The spec only describes About's *initial*
  // state ("open by default"), not an invariant that some section must
  // always be expanded, so this is intentional, not an oversight.
  void _toggleSection(_Section s) {
    setState(() => _openSection = _openSection == s ? null : s);
  }

  String? _distanceLabel(Gem gem) {
    final pos = _userPos;
    if (pos == null || !gem.hasCoords) return null;
    return gemDistanceLabel(Geolocator.distanceBetween(
        pos.latitude, pos.longitude, gem.latitude!, gem.longitude!));
  }

  // "~45 min" under an hour, "~1h 30m" / "~2h" once it rolls over — same
  // raw-minutes source (`saved_gems.est_duration_min`) the Itinerary's
  // planned-time rollup already reads, just formatted for a one-line quick
  // fact here instead of a sum. Null (unset) never renders as "0" or "TBD"
  // — the caller only shows this when it has a real value.
  String? _visitLengthLabel(Gem gem) {
    final min = gem.estDurationMin;
    if (min == null || min <= 0) return null;
    if (min < 60) return '~${min}min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '~${h}h' : '~${h}h ${m}m';
  }

  Future<void> _openDirections(Gem gem) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${gem.latitude},${gem.longitude}');
    final launched = await attemptExternalLaunch(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open maps")),
      );
    }
  }

  // Copies a link, doesn't open a native share sheet — no share_plus (or
  // equivalent) dependency exists anywhere in this app yet, and adding one
  // is a bigger change than this screen's redesign calls for. Label/icon
  // say "Copy Link" rather than "Share" so the control doesn't promise more
  // than it does; wiring a real share sheet is a reasonable follow-up.
  void _copyLink(Gem gem) {
    Clipboard.setData(
        ClipboardData(text: 'Check out "${gem.gemName}" on Explorife!'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied!')),
    );
  }

  // A POI-derived gem has no saved_gems row, so there's nothing for
  // gem_saves to reference — same "coming soon" message the POI's own card
  // already shows for its bookmark icon (destination_landing_screen.dart's
  // PoiResultCard), rather than attempting a real save that would just fail.
  void _comingSoonSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving places is coming soon')),
    );
  }

  /// Gated on a real account (see requireAccount's own doc) — a guest CAN
  /// technically save a gem at the RLS layer, but a save tied to a
  /// disposable anonymous session is unrecoverable the moment that session
  /// is lost, so this is one of the actions the guest-browsing model
  /// deliberately still asks for sign-in on. The gemId is persisted before
  /// the sign-in redirect fires, so completing sign-in re-runs the save
  /// automatically instead of the tap silently going nowhere — see
  /// resolvePendingAction's 'save_gem' case.
  Future<void> _toggleSave(Gem gem) async {
    if (!await requireAccount(context,
        action: 'save_gem',
        payload: {'gemId': gem.id},
        reason: 'Sign in to save this gem and find it again anytime.')) {
      return;
    }
    if (!mounted) return;
    await context.read<GemProvider>().toggleSave(gem);
  }

  /// Adds this gem to the active trip's Day 1 / Morning slot, then confirms
  /// with a "View Trip" snackbar so the user can immediately re-file it into
  /// the right day/slot if this default doesn't match where they actually
  /// want it — see this file's class doc for why Day 1/Morning specifically.
  void _addToTrip(Gem gem, Trip trip) {
    final tripProv = context.read<TripProvider>();
    if (gem.isFromPoi) {
      tripProv.addStop(
        tripId: trip.id,
        day: 1,
        slot: 'morning',
        customPayload: {
          'title': gem.gemName,
          if (gem.latitude != null) 'lat': gem.latitude,
          if (gem.longitude != null) 'lng': gem.longitude,
        },
      );
    } else {
      tripProv.addStop(
          tripId: trip.id, day: 1, slot: 'morning', gemId: gem.id);
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to ${trip.displayName}'),
        action: SnackBarAction(
          label: 'View Trip',
          onPressed: () => context.push('/trips/${trip.id}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.lightSurface,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_gem == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightSurface,
        appBar: AppBar(backgroundColor: AppTheme.lightSurface),
        body: Center(
            child: Text('Gem not found',
                style: GoogleFonts.fredoka(color: AppTheme.lightMute))),
      );
    }

    final gem = _gem!;
    final photos = gem.allPhotos;
    final gemProv = context.watch<GemProvider>();
    final tripProv = context.watch<TripProvider>();
    final isSaved = !gem.isFromPoi && gemProv.isSaved(gem.id);
    // POI-derived stops carry no gemId (see gemAlreadyOnTrip's doc comment)
    // — there's no reliable way to detect an existing duplicate for those,
    // so this guard only covers real, curated gems.
    final alreadyOnTrip = !gem.isFromPoi &&
        tripProv.activeTrip != null &&
        gemAlreadyOnTrip(gem, tripProv.stopsFor(tripProv.activeTrip!.id));

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      // The sticky CTA deliberately lives inside `body` (as a Positioned
      // overlay in a Stack) rather than Scaffold.bottomNavigationBar: on
      // this screen, the Text inside _StickyCta's button left `body` never
      // painting again after the loading -> loaded transition (no exception
      // anywhere — same CanvasKit/Flutter-web bug already diagnosed and
      // fixed the same way on TourDetailScreen; see that screen's build()
      // for the original bisection notes). Moving the bar into a Stack
      // inside body sidesteps whatever Scaffold-level body/
      // bottomNavigationBar interaction that is.
      //
      // The mobile/desktop split below is a LayoutBuilder against this
      // Stack's own constraints, NOT Breakpoints.isDesktop(context)'s
      // MediaQuery-based window width: this screen renders inside
      // AppShell's ShellRoute (see app_router.dart's '/gems/:id'), whose
      // side-nav rail already eats into the window width on desktop.
      // Comparing the window width directly would flip to the desktop
      // layout too early on a viewport where the actual space left for
      // this body is still narrow — exactly the case Breakpoints' own doc
      // comment calls out, and the same reason TripBuilderScreen compares
      // constraints.maxWidth instead of the window width for its own
      // desktop split.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= Breakpoints.desktop;
          return Stack(
            children: [
              Positioned.fill(
                child: isDesktop
                    ? _buildDesktopBody(
                        gem,
                        photos,
                        activeTrip: tripProv.activeTrip,
                        alreadyOnTrip: alreadyOnTrip,
                      )
                    : _buildScrollableBody(gem, photos),
              ),
              // Desktop-only: the trip-aware primary action this bar used to
              // own now lives in _QuickActionRow's fourth slot instead (see
              // that class's doc comment), and Save is already redundant on
              // desktop (top action row + hero-photo overlay icon) — so the
              // whole bar is redundant there too. Still the fastest one-tap
              // path on mobile/narrow widths, where it's kept unchanged.
              if (!isDesktop)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: AppTheme.lightSurface,
                    child: _StickyCta(
                      gem: gem,
                      activeTrip: tripProv.activeTrip,
                      alreadyOnTrip: alreadyOnTrip,
                      isSaved: isSaved,
                      canDirections: gem.hasCoords,
                      onDirections:
                          gem.hasCoords ? () => _openDirections(gem) : null,
                      onSave: gem.isFromPoi
                          ? _comingSoonSave
                          : () => _toggleSave(gem),
                      onAddToTrip: _addToTrip,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScrollableBody(Gem gem, List<String> photos) {
    final gemProv = context.watch<GemProvider>();
    final isSaved = !gem.isFromPoi && gemProv.isSaved(gem.id);
    final distance = _distanceLabel(gem);
    final hasAbout = _hasAbout(gem);
    final hasLocation = _hasLocation(gem);
    final visitLength = _visitLengthLabel(gem);
    final bestTime = gem.bestTimeToVisit;
    final hasBestTime = bestTime != null && bestTime.isNotEmpty;
    return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _heroCarousel(
              gem,
              photos,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/explore'),
              onCopyLink: () => _copyLink(gem),
              isSaved: isSaved,
              onToggleSave: gem.isFromPoi
                  ? _comingSoonSave
                  : () => _toggleSave(gem),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _bodyColumn(
                gem,
                distance: distance,
                hasAbout: hasAbout,
                hasLocation: hasLocation,
                visitLength: visitLength,
                bestTime: bestTime,
                hasBestTime: hasBestTime,
                isSaved: isSaved,
                showDirections: true,
              ),
            ),
          ),
          if (_nearby.isNotEmpty)
            SliverToBoxAdapter(child: _NearbyExperiences(pois: _nearby)),
          // Clears the sticky bottom CTA, which is now a Positioned overlay
          // (see build()'s doc comment) rather than Scaffold.
          // bottomNavigationBar — that stopped reserving layout space for
          // it, so this padding is what actually keeps the last scrolled
          // content from ending up hidden behind it. ~96 covers the CTA's
          // ~50px button + its own vertical padding with a little extra
          // clearance; there's no device bottom-inset to add on web.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
    );
  }

  // ── Desktop (>=Breakpoints.desktop content width): two-column layout —
  // ~62% left column (photo grid, title/location, condensed actions, About/
  // Good to Know/Location accordions — same accordion structure as mobile,
  // deliberately not flattened — and the Nearby Experiences strip), ~38%
  // right column with a single-pin map + "Get directions", which never
  // scrolls with the left column since it lives outside that column's own
  // CustomScrollView rather than inside a shared one.
  Widget _buildDesktopBody(
    Gem gem,
    List<String> photos, {
    required Trip? activeTrip,
    required bool alreadyOnTrip,
  }) {
    final gemProv = context.watch<GemProvider>();
    final isSaved = !gem.isFromPoi && gemProv.isSaved(gem.id);
    final distance = _distanceLabel(gem);
    final hasAbout = _hasAbout(gem);
    final hasLocation = _hasLocation(gem);
    final visitLength = _visitLengthLabel(gem);
    final bestTime = gem.bestTimeToVisit;
    final hasBestTime = bestTime != null && bestTime.isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 62,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                      child: _photoGrid(
                        gem,
                        photos,
                        onBack: () => context.canPop()
                            ? context.pop()
                            : context.go('/explore'),
                        onCopyLink: () => _copyLink(gem),
                        isSaved: isSaved,
                        onToggleSave: gem.isFromPoi
                            ? _comingSoonSave
                            : () => _toggleSave(gem),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                      child: _bodyColumn(
                        gem,
                        distance: distance,
                        hasAbout: hasAbout,
                        hasLocation: hasLocation,
                        visitLength: visitLength,
                        bestTime: bestTime,
                        hasBestTime: hasBestTime,
                        isSaved: isSaved,
                        // Directions moves to the map sidebar on desktop —
                        // the one action that reads better next to the map
                        // than in this top row (item 4/8 of the redesign).
                        showDirections: false,
                        activeTrip: activeTrip,
                        alreadyOnTrip: alreadyOnTrip,
                      ),
                    ),
                  ),
                  if (_nearby.isNotEmpty)
                    SliverToBoxAdapter(
                        child: _NearbyExperiences(pois: _nearby)),
                  // Plain trailing breathing room — unlike mobile's matching
                  // block, this isn't clearing a sticky CTA: desktop's
                  // sticky bar is hidden (see build()'s `!isDesktop` gate).
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 24, 24),
                child: _GemMapSidebar(
                  gem: gem,
                  onDirections:
                      gem.hasCoords ? () => _openDirections(gem) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared header + content column — category/effort/distance line,
  // title, location, above-the-fold quick facts, the Save/Copy-link (and,
  // on mobile, Directions too) action row, then the About/Good to Know/
  // Location accordions and any linked-business cards. Identical between
  // the mobile single column and the desktop left column; [showDirections]
  // is the only behavioral difference (desktop drops Directions from this
  // row since it lives in the map sidebar instead — see
  // _buildDesktopBody/_GemMapSidebar).
  Widget _bodyColumn(
    Gem gem, {
    required String? distance,
    required bool hasAbout,
    required bool hasLocation,
    required String? visitLength,
    required String? bestTime,
    required bool hasBestTime,
    required bool isSaved,
    required bool showDirections,
    // Only passed by _buildDesktopBody — see _QuickActionRow's doc comment
    // on why that's what gates its fourth "add to trip" slot to desktop.
    Trip? activeTrip,
    bool alreadyOnTrip = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category + effort + distance-away, one line. The effort pill
        // reuses `gem.difficulty` (Easy/Moderate/Hard) but deliberately
        // with a neutral bolt icon and no "Difficulty" wording — that field
        // predates non-hiking categories, and a landmark/temple showing a
        // hiking-trail-difficulty framing reads wrong. The About
        // accordion's own tile below still spells out "Difficulty" for
        // anyone who opens it; this top-line pill is just a same-glance
        // effort cue.
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text('${gem.emoji}  ${gem.displayCategory}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: AppTheme.primary)),
          ),
          if (gem.difficulty != null && gem.difficulty!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.lightCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_outlined,
                    size: 12, color: AppTheme.lightMute),
                const SizedBox(width: 4),
                Text(gem.difficulty!,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: AppTheme.lightMute)),
              ]),
            ),
          ],
          if (distance != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.near_me_outlined,
                size: 13, color: AppTheme.lightMute),
            const SizedBox(width: 3),
            Text(distance,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: AppTheme.lightMute)),
          ],
        ]),
        const SizedBox(height: 12),

        Text(gem.gemName,
            style: GoogleFonts.bebasNeue(
                fontSize: 36, color: AppTheme.lightInk, letterSpacing: 0.5)),
        // No rating field exists anywhere in the data model today (no
        // review-aggregation source, by design — see this screen's earlier
        // editorial-content work) — this line is just the location, never
        // a fabricated star rating.
        if (gem.gemLocation != null && gem.gemLocation!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 14, color: AppTheme.lightMute),
            const SizedBox(width: 4),
            Expanded(
              child: Text(gem.gemLocation!,
                  style: GoogleFonts.fredoka(
                      fontSize: 13, color: AppTheme.lightMute)),
            ),
          ]),
        ],
        // Quick facts, above the fold and independent of the About
        // accordion below (which still spells out the same best-time value
        // for anyone who opens it — deliberate, not a bug: a same-glance
        // summary here doesn't mean the accordion's own detail line has to
        // go). No "Entry Fee" here — there's no such field anywhere in
        // Gem/saved_gems today, and the real gem set is overwhelmingly free
        // public places/landmarks, so a row entry would mean either
        // fabricating a value or always guessing "Free". The one case that
        // would actually matter (paid vs. free temple entry) is a
        // data-model gap for the team to add a real field for, not
        // something to invent in this widget.
        if (visitLength != null || hasBestTime) ...[
          const SizedBox(height: 14),
          Row(children: [
            if (visitLength != null)
              _QuickFact(
                  icon: Icons.schedule,
                  label: 'Visit length',
                  value: visitLength),
            if (visitLength != null && hasBestTime) const SizedBox(width: 20),
            if (hasBestTime)
              _QuickFact(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Best time',
                  value: bestTime!),
          ]),
        ],
        const SizedBox(height: 16),

        _QuickActionRow(
          canDirections: gem.hasCoords,
          onDirections: gem.hasCoords ? () => _openDirections(gem) : null,
          isSaved: isSaved,
          onToggleSave:
              gem.isFromPoi ? _comingSoonSave : () => _toggleSave(gem),
          onCopyLink: () => _copyLink(gem),
          showDirections: showDirections,
          gem: gem,
          activeTrip: activeTrip,
          alreadyOnTrip: alreadyOnTrip,
          onAddToTrip: activeTrip != null ? _addToTrip : null,
        ),
        const SizedBox(height: 20),

        if (hasAbout)
          _AccordionSection(
            title: 'About',
            isOpen: _openSection == _Section.about,
            onTap: () => _toggleSection(_Section.about),
            child: _aboutContent(gem),
          ),
        if (gem.goodToKnow.isNotEmpty)
          _AccordionSection(
            title: 'Good to Know',
            isOpen: _openSection == _Section.goodToKnow,
            onTap: () => _toggleSection(_Section.goodToKnow),
            child: _goodToKnowContent(gem),
          ),
        if (hasLocation)
          _AccordionSection(
            title: 'Location',
            isOpen: _openSection == _Section.location,
            onTap: () => _toggleSection(_Section.location),
            child: _locationContent(gem, distance),
          ),
        // A verified business listing for this same place, if one exists —
        // deliberately NOT folded into the accordion above: the curated
        // content there is untouched by whether a business has claimed
        // this place, and this reads as its own distinct,
        // business-attributed section rather than editorial content. An
        // Attraction and a Restaurant can both legitimately link to the
        // same Gem (see _linkedRestaurant's doc comment), so both cards can
        // show at once.
        if (_linkedAttraction != null) ...[
          const SizedBox(height: 16),
          _attractionCard(_linkedAttraction!),
        ],
        if (_linkedRestaurant != null) ...[
          const SizedBox(height: 16),
          _restaurantCard(_linkedRestaurant!),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _attractionCard(Attraction attraction) => LinkedBusinessCard(
        detailRoute: '/attractions/${attraction.id}',
        rows: [
          LinkedBusinessInfoRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Entry Fee',
            value: attraction.isFree
                ? 'Free'
                : '${attraction.currency} ${attraction.entryFeeAmount}',
          ),
          LinkedBusinessInfoRow(
            icon: Icons.schedule,
            label: 'Opening Hours',
            value: attraction.openingHours,
          ),
          if (attraction.recommendedDuration != null &&
              attraction.recommendedDuration!.isNotEmpty)
            LinkedBusinessInfoRow(
              icon: Icons.hourglass_empty,
              label: 'Recommended Duration',
              value: attraction.recommendedDuration!,
            ),
        ],
      );

  Widget _restaurantCard(Restaurant restaurant) => LinkedBusinessCard(
        detailRoute: '/restaurants/${restaurant.id}',
        rows: [
          LinkedBusinessInfoRow(
            icon: Icons.payments_outlined,
            label: 'Price Range',
            value: restaurant.priceRange.wire,
          ),
          LinkedBusinessInfoRow(
            icon: Icons.schedule,
            label: 'Opening Hours',
            value: restaurant.openingHours,
          ),
          LinkedBusinessInfoRow(
            icon: Icons.event_seat_outlined,
            label: 'Reservations',
            value: restaurant.reservationOption
                ? 'Reservations accepted'
                : 'Walk-ins only',
          ),
        ],
      );

  Widget _aboutContent(Gem gem) {
    final hasDifficulty = gem.difficulty != null && gem.difficulty!.isNotEmpty;
    final hasBestTime =
        gem.bestTimeToVisit != null && gem.bestTimeToVisit!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gem.description != null && gem.description!.isNotEmpty) ...[
          Text(gem.description!,
              style: GoogleFonts.fredoka(
                  fontSize: 14, color: AppTheme.lightMute, height: 1.6)),
          const SizedBox(height: 14),
        ],
        // Difficulty and Best Time share one boxed row with a divider
        // between them, rather than two full-width stacked tiles — the
        // same side-by-side quick-facts convention QuickFactsRow/
        // QuickFactCell already use on the tour detail screen and tour
        // cards (lib/widgets/tours/tour_detail_shared.dart).
        if (hasDifficulty || hasBestTime)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Row(children: [
              if (hasDifficulty)
                Expanded(
                  child: _InfoTileContent(
                      icon: Icons.trending_up_rounded,
                      label: 'Difficulty',
                      value: gem.difficulty!),
                ),
              if (hasDifficulty && hasBestTime)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 32,
                    child: VerticalDivider(width: 1, color: AppTheme.lightBorder),
                  ),
                ),
              if (hasBestTime)
                Expanded(
                  child: _InfoTileContent(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Best Time',
                      value: gem.bestTimeToVisit!),
                ),
            ]),
          ),
      ],
    );
  }

  // NOTE: the redesign spec calls for an hours table alongside the tips
  // list here — there's no structured hours field anywhere in the Gem model
  // (confirmed before building this; `goodToKnow` is free-text tips only),
  // so only the tips list renders. Adding real opening-hours data is a
  // separate, larger change (new field + migration + curation work), out of
  // scope for this screen redesign.
  Widget _goodToKnowContent(Gem gem) {
    final tips = gem.goodToKnow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tips.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tips[i],
                      style: GoogleFonts.fredoka(
                          fontSize: 13.5,
                          color: AppTheme.lightMute,
                          height: 1.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _locationContent(Gem gem, String? distance) {
    final hasMap = gem.hasCoords;
    final overlay = hasMap
        ? GeocodingService.buildStaticMapOverlay(pins: [
            (lat: gem.latitude!, lng: gem.longitude!, label: '', color: 'FF6B35'),
          ])
        : null;
    final mapUrl = hasMap
        ? GeocodingService.staticImageUrl(
            lat: gem.latitude!,
            lng: gem.longitude!,
            zoom: 14,
            width: 600,
            height: 300,
            // Deliberate, not a leftover — same low-chrome dark map crop
            // placement_screen.dart's embedded map already uses on this
            // app's light UI (see its comment on why: a flat dark style
            // reads cleaner as a small embedded crop than this app's usual
            // light map).
            styleId: 'dark-v11',
            overlay: overlay,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gem.gemLocation != null && gem.gemLocation!.isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.place_outlined, size: 15, color: AppTheme.lightMute),
            const SizedBox(width: 6),
            Expanded(
              child: Text(gem.gemLocation!,
                  style: GoogleFonts.fredoka(
                      fontSize: 13.5, color: AppTheme.lightInk)),
            ),
          ]),
          const SizedBox(height: 6),
        ],
        if (distance != null) ...[
          Row(children: [
            const Icon(Icons.near_me_outlined, size: 14, color: AppTheme.lightMute),
            const SizedBox(width: 6),
            Text('$distance away',
                style: GoogleFonts.fredoka(
                    fontSize: 13, color: AppTheme.lightMute)),
          ]),
          const SizedBox(height: 10),
        ],
        if (hasMap)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: mapUrl != null
                  ? AppNetworkImage(
                      url: mapUrl, semanticLabel: 'Map of ${gem.gemName}')
                  : Container(color: AppTheme.lightSurface),
            ),
          ),
      ],
    );
  }

  // ── Hero photo carousel: floating overlay controls (back top-left, save +
  // share top-right, per the reference) + dot-indicator pagination, one
  // component whether there's 0, 1, or many photos — never a different
  // layout for the single-photo case.
  Widget _heroCarousel(
    Gem gem,
    List<String> photos, {
    required VoidCallback onBack,
    required VoidCallback onCopyLink,
    required bool isSaved,
    required VoidCallback onToggleSave,
  }) {
    // A POI-derived gem carries Mapbox's own Maki icon — the same specific
    // glyph (building, parking, etc.) its card already shows — instead of
    // the generic pin emoji a catalogue gem with no photo falls back to.
    return PhotoCarousel(
      photos: photos,
      captionFor: gem.captionFor,
      emptyIcon: gem.maki != null ? NearbyPoi.iconForMaki(gem.maki) : null,
      emptyEmoji: gem.maki == null ? gem.emoji : null,
      semanticLabel: gem.gemName,
      showIndexBadge: true,
      topLeft:
          _HeaderIcon(icon: Icons.arrow_back, onTap: onBack, label: 'Back'),
      topRight: Row(children: [
        _HeaderIcon(
          icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
          onTap: onToggleSave,
          iconColor: isSaved ? AppTheme.primary : Colors.white,
          label: isSaved ? 'Saved' : 'Save',
        ),
        const SizedBox(width: 8),
        _HeaderIcon(
            icon: Icons.link_rounded, onTap: onCopyLink, label: 'Copy link'),
      ]),
    );
  }

  // ── Desktop-only photo grid: one large photo + up to 3 stacked
  // thumbnails, contained to the left column's width rather than
  // full-bleed like _heroCarousel's PhotoCarousel. A "+N" overlay on the
  // last thumbnail covers any photos beyond what fits (large + 3 thumbs =
  // 4 shown). Same overlay controls (back/save/copy-link) as the mobile
  // hero, just anchored over the large tile instead of the full-width one.
  Widget _photoGrid(
    Gem gem,
    List<String> photos, {
    required VoidCallback onBack,
    required VoidCallback onCopyLink,
    required bool isSaved,
    required VoidCallback onToggleSave,
  }) {
    final overlayControls = Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _HeaderIcon(icon: Icons.arrow_back, onTap: onBack, label: 'Back'),
          Row(children: [
            _HeaderIcon(
              icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
              onTap: onToggleSave,
              iconColor: isSaved ? AppTheme.primary : Colors.white,
              label: isSaved ? 'Saved' : 'Save',
            ),
            const SizedBox(width: 8),
            _HeaderIcon(
                icon: Icons.link_rounded, onTap: onCopyLink, label: 'Copy link'),
          ]),
        ],
      ),
    );

    if (photos.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 280,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: AppTheme.lightCard,
                alignment: Alignment.center,
                child: gem.maki != null
                    ? Icon(NearbyPoi.iconForMaki(gem.maki),
                        size: 56, color: AppTheme.lightMute)
                    : Text(gem.emoji, style: const TextStyle(fontSize: 56)),
              ),
              overlayControls,
            ],
          ),
        ),
      );
    }

    // Up to 3 thumbnails beside the large cover photo; anything past that
    // (large + 3 thumbs = 4 shown) is summarized by the last thumbnail's
    // "+N" overlay rather than growing the grid unboundedly.
    final thumbs = photos.skip(1).take(3).toList();
    final extra = photos.length - 4;
    const scrim = Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59000000), Colors.transparent],
          ),
        ),
      ),
    );

    return SizedBox(
      height: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: thumbs.isEmpty ? 1 : 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(url: photos[0], semanticLabel: gem.gemName),
                  scrim,
                  overlayControls,
                ],
              ),
            ),
          ),
          if (thumbs.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  for (var i = 0; i < thumbs.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AppNetworkImage(
                                url: thumbs[i], semanticLabel: gem.gemName),
                            if (i == thumbs.length - 1 && extra > 0)
                              Container(
                                color: Colors.black.withValues(alpha: 0.5),
                                alignment: Alignment.center,
                                child: Text('+$extra',
                                    style: GoogleFonts.jetBrainsMono(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final String label;
  const _HeaderIcon(
      {required this.icon,
      required this.onTap,
      required this.label,
      this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// One above-the-fold quick fact (icon + small label + value), stacked
/// two-across in the Row that builds it. Deliberately not [_InfoTile]'s
/// boxed style — that's the About accordion's look; this is meant to read
/// as a lighter same-glance summary line, not a second copy of the same box.
class _QuickFact extends StatelessWidget {
  const _QuickFact(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: AppTheme.primary),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5, color: AppTheme.lightMute)),
        Text(value,
            style: GoogleFonts.fredoka(
                fontSize: 13, color: AppTheme.lightInk)),
      ]),
    ]);
  }
}

/// Directions / Save / Share, equal-width, Directions leftmost — per the
/// redesign spec. [onDirections] null (→ visually disabled, not hidden, to
/// keep the three-way equal-width layout stable) when the gem has no
/// coordinates to route to.
class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.canDirections,
    required this.onDirections,
    required this.isSaved,
    required this.onToggleSave,
    required this.onCopyLink,
    this.showDirections = true,
    this.gem,
    this.activeTrip,
    this.alreadyOnTrip = false,
    this.onAddToTrip,
  });

  final bool canDirections;
  final VoidCallback? onDirections;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onCopyLink;

  /// False on the desktop two-column layout, where Directions lives below
  /// the map sidebar instead — this row then condenses to Save + Copy Link
  /// (+ the trip slot below, when it applies) — item 4 of the desktop
  /// redesign. True everywhere else (mobile), unchanged from before that
  /// redesign.
  final bool showDirections;

  // Fourth slot — desktop only. Mirrors _StickyCta's own trip-aware primary
  // action (see that class's doc comment) now that the sticky bar itself is
  // hidden on desktop (see build()'s `!isDesktop` gate). Only
  // _buildDesktopBody passes [activeTrip]/[onAddToTrip]; _buildScrollableBody
  // (mobile) leaves them null, so mobile never shows this slot and keeps
  // relying on _StickyCta for it, unchanged.
  final Gem? gem;
  final Trip? activeTrip;
  final bool alreadyOnTrip;
  final void Function(Gem gem, Trip trip)? onAddToTrip;

  @override
  Widget build(BuildContext context) {
    final trip = activeTrip;
    final thisGem = gem;
    final addToTrip = onAddToTrip;
    final showTripSlot = trip != null && thisGem != null && addToTrip != null;

    String tripLabel = '';
    VoidCallback? tripOnTap;
    IconData tripIcon = Icons.playlist_add_outlined;
    if (showTripSlot) {
      if (alreadyOnTrip) {
        tripLabel = '✓ Added to ${trip.displayName}';
        tripIcon = Icons.playlist_add_check;
        tripOnTap = () => context.push('/trips/${trip.id}');
      } else {
        tripLabel = '+ Add to my ${trip.displayName} trip';
        tripOnTap = () => addToTrip(thisGem, trip);
      }
    }

    // When the trip slot is showing, it takes over as *the* primary action
    // in this row — mirroring _StickyCta's own priority of "add to trip"
    // over Save (see that class's doc comment) — rather than leaving Save's
    // highlighted "Saved" state competing for attention next to a second
    // highlighted button. Save still works exactly the same when tapped;
    // only its filled/highlighted styling is demoted.
    final saveIsPrimary = !showTripSlot;

    return Row(children: [
      if (showDirections) ...[
        Expanded(
          child: _QuickActionButton(
            icon: Icons.directions_outlined,
            label: 'Directions',
            onTap: onDirections,
          ),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: _QuickActionButton(
          icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
          label: isSaved ? 'Saved' : 'Save',
          onTap: onToggleSave,
          active: isSaved && saveIsPrimary,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QuickActionButton(
          icon: Icons.link_rounded,
          label: 'Copy Link',
          onTap: onCopyLink,
        ),
      ),
      if (showTripSlot) ...[
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            icon: tripIcon,
            label: tripLabel,
            onTap: tripOnTap,
            active: true,
          ),
        ),
      ],
    ]);
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? AppTheme.lightMute.withValues(alpha: 0.45)
        : (active ? AppTheme.primary : AppTheme.lightInk);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? AppTheme.primary.withValues(alpha: 0.4)
                    : AppTheme.lightBorder,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(height: 4),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "additional section" a verified business listing surfaces as on Gem
/// Detail — see docs/audits/attraction-business-profile-2026-09-04.md.
/// One collapsible section — single-open accordion, driven entirely by the
/// parent screen's [_Section] state (this widget holds no state of its
/// own). Sections that have no data for this gem are never even given one
/// of these; see `_hasAbout`/`_hasLocation`/`goodToKnow.isNotEmpty` in the
/// screen state above.
class _AccordionSection extends StatelessWidget {
  const _AccordionSection({
    required this.title,
    required this.isOpen,
    required this.onTap,
    required this.child,
  });

  final String title;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: GoogleFonts.bebasNeue(
                              fontSize: 18,
                              letterSpacing: 0.5,
                              color: AppTheme.lightInk)),
                    ),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppTheme.lightMute),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState:
                isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

/// Icon + label/value pair — the inner content of the About card's
/// Difficulty/Best Time cells. No box of its own: [_aboutContent] wraps
/// both instances (and the divider between them) in one shared bordered
/// container, rather than each tile boxing itself individually the way the
/// old two-full-width-rows layout did.
class _InfoTileContent extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTileContent(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppTheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.lightMute)),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
        ]),
      ),
    ]);
  }
}

/// Sticky primary CTA, always visible while scrolling — mobile/narrow
/// widths only (see build()'s `!isDesktop` gate; it lives as a Positioned
/// overlay in the Scaffold's body, not `bottomNavigationBar` — see that
/// same build() doc comment for why). On desktop this same trip-aware
/// primary action instead lives in _QuickActionRow's fourth slot, and Save
/// is already covered by the top action row + hero-photo overlay icon, so
/// the whole bar is redundant there and hidden rather than duplicated.
/// Paired with a small square icon-only Directions button. Primary action:
///
///  - An active trip exists (TripProvider.activeTrip — the soonest trip
///    starting within 30 days): "+ Add to my {trip} trip", adding this gem
///    as a Day 1 / Morning stop (see _addToTrip's doc comment for why that
///    specific default) and confirming with a "View Trip" snackbar.
///  - No active trip: falls back to Save/Saved — the resolved "Open
///    decision": this app's trip-planning feature is real (TripProvider,
///    TripStop, an active-trip concept, a real addStop API used elsewhere
///    already for Trip Builder's Add Stop sheet), so this CTA is not
///    placeholder copy for an unbuilt feature — it's simply inert when
///    there's genuinely no trip to add to right now.
class _StickyCta extends StatelessWidget {
  const _StickyCta({
    required this.gem,
    required this.activeTrip,
    required this.alreadyOnTrip,
    required this.isSaved,
    required this.canDirections,
    required this.onDirections,
    required this.onSave,
    required this.onAddToTrip,
  });

  final Gem gem;
  final Trip? activeTrip;
  // Whether [gem] is already a stop on [activeTrip] — see
  // gemAlreadyOnTrip's doc comment for why. When true, tapping the button
  // goes to View Trip instead of calling addStop again, so a double-tap
  // (slow network, impatient user) can't create a duplicate stop.
  final bool alreadyOnTrip;
  final bool isSaved;
  final bool canDirections;
  final VoidCallback? onDirections;
  final VoidCallback onSave;
  final void Function(Gem gem, Trip trip) onAddToTrip;

  @override
  Widget build(BuildContext context) {
    final trip = activeTrip;
    final String label;
    final VoidCallback onTap;
    if (trip != null && alreadyOnTrip) {
      label = '✓ Added to ${trip.displayName}';
      onTap = () => context.push('/trips/${trip.id}');
    } else if (trip != null) {
      label = '+ Add to my ${trip.displayName} trip';
      onTap = () => onAddToTrip(gem, trip);
    } else {
      label = isSaved ? 'Saved' : 'Save';
      onTap = onSave;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fredoka(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          if (canDirections) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 50,
              height: 50,
              child: Semantics(
                button: true,
                label: 'Get directions',
                child: OutlinedButton(
                  onPressed: onDirections,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Icon(Icons.directions_outlined, size: 22),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Real nearby POIs (any category — cafes, viewpoints, landmarks...) around
/// this gem's coordinates, via the same [MapboxTilequeryService] the
/// destination landing page's "Nearby" section already uses. Mapbox Tilequery
/// never returns a photo for any result (confirmed against the raw API
/// response), so each card shows a category icon on a tinted tile instead of
/// a fabricated image.
class _NearbyExperiences extends StatelessWidget {
  final List<NearbyPoi> pois;
  const _NearbyExperiences({required this.pois});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Nearby Experiences',
                style: GoogleFonts.bebasNeue(
                    fontSize: 20,
                    letterSpacing: 0.5,
                    color: AppTheme.lightInk)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: pois.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _NearbyCard(poi: pois[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final NearbyPoi poi;
  const _NearbyCard({required this.poi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Container(
                color: AppTheme.primary.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(NearbyPoi.iconForMaki(poi.maki),
                    size: 26, color: AppTheme.primary),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name,
                    style: GoogleFonts.fredoka(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (poi.distanceMeters != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    poi.distanceMeters! < 1000
                        ? '${poi.distanceMeters!.round()} m'
                        : '${(poi.distanceMeters! / 1000).toStringAsFixed(1)} km',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: AppTheme.lightMute),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Right-column sticky map for the desktop two-column layout — a single pin
/// at this gem's own coordinates. Reuses the same MapEngineView/
/// MapMarkerData plumbing the itinerary's day map (trip_day_map.dart) and
/// full-trip map (trip_map_dialog.dart) already use, rather than inventing
/// a second map stack just for this screen — only new to *this screen*,
/// not to the app. Distinct from _locationContent's embedded map, which
/// stays the flat Mapbox Static Images crop inside the About/Location
/// accordion — a deliberately low-chrome afterthought there, not this
/// column's interactive centerpiece.
class _GemMapSidebar extends StatefulWidget {
  const _GemMapSidebar({required this.gem, required this.onDirections});

  final Gem gem;
  final VoidCallback? onDirections;

  @override
  State<_GemMapSidebar> createState() => _GemMapSidebarState();
}

class _GemMapSidebarState extends State<_GemMapSidebar> {
  static final String _token = dotenv.env['MAPBOX_TOKEN'] ?? '';

  // Same web-vs-native style split as trip_day_map.dart/trip_map_dialog.dart,
  // and for the same reason (Standard Style's 3D buildings/dynamic lighting
  // only render through a real Mapbox GL runtime).
  String get _styleId => kIsWeb ? 'standard' : 'outdoors-v12';

  MapEngineController? _controller;
  bool _fitted = false;

  MapMarkerData get _marker => MapMarkerData(
        id: widget.gem.id,
        lat: widget.gem.latitude!,
        lng: widget.gem.longitude!,
        emoji: widget.gem.emoji,
        icon: Icons.place,
        color: AppTheme.primary,
      );

  void _onReady(MapEngineController controller) {
    _controller = controller;
    if (_fitted) return;
    _fitted = true;
    // One marker, so this just centers on it at fitMarkers' own default
    // single-point zoom — same shape as trip_day_map.dart's _maybeFit, but
    // with nothing to key off of since this map never changes markers.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _controller?.fitMarkers([_marker]));
  }

  @override
  Widget build(BuildContext context) {
    final hasMap = widget.gem.hasCoords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 260,
            decoration: BoxDecoration(
              color: AppTheme.lightCard,
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: hasMap
                ? MapEngineView(
                    markers: [_marker],
                    styleId: _styleId,
                    token: _token,
                    onMarkerTap: (_) {},
                    onReady: _onReady,
                    // Read-only pin preview — no pan/zoom/keyboard capture,
                    // so the wheel/keyboard stay with the surrounding page's
                    // scroll view instead of the map. See map_engine_web.dart.
                    interactive: false,
                  )
                : Center(
                    child: Text('Location not available',
                        style: GoogleFonts.fredoka(
                            fontSize: 13, color: AppTheme.lightMute)),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _DirectionsButton(onTap: widget.onDirections),
      ],
    );
  }
}

/// Full-width primary-styled button below the map sidebar — the one
/// "Directions" action that reads better next to the map than in the top
/// action row on desktop (see _QuickActionRow's showDirections). Disabled
/// (greyed, no-op) rather than hidden when the gem has no coordinates, same
/// "never fabricate, never silently vanish" rule the rest of this screen
/// follows for optional data.
class _DirectionsButton extends StatelessWidget {
  const _DirectionsButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      label: 'Get directions',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: disabled ? AppTheme.lightCard : AppTheme.primary,
              borderRadius: BorderRadius.circular(14),
              border: disabled ? Border.all(color: AppTheme.lightBorder) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_outlined,
                    size: 18,
                    color: disabled
                        ? AppTheme.lightMute.withValues(alpha: 0.6)
                        : Colors.white),
                const SizedBox(width: 8),
                Text('Get directions',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: disabled ? AppTheme.lightMute : Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

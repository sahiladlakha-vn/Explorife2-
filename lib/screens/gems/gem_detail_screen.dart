import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../../widgets/common/photo_carousel.dart';
import '../../widgets/gems/linked_business_card.dart';
import '../explore/feed_metrics.dart';

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
    final distance = _distanceLabel(gem);
    final hasAbout = _hasAbout(gem);
    final hasLocation = _hasLocation(gem);
    // POI-derived stops carry no gemId (see gemAlreadyOnTrip's doc comment)
    // — there's no reliable way to detect an existing duplicate for those,
    // so this guard only covers real, curated gems.
    final alreadyOnTrip = !gem.isFromPoi &&
        tripProv.activeTrip != null &&
        gemAlreadyOnTrip(gem, tripProv.stopsFor(tripProv.activeTrip!.id));

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: CustomScrollView(
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
                  : () => context.read<GemProvider>().toggleSave(gem),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + distance-away, one line.
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text('${gem.emoji}  ${gem.displayCategory}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: AppTheme.primary)),
                    ),
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
                          fontSize: 36,
                          color: AppTheme.lightInk,
                          letterSpacing: 0.5)),
                  // No rating field exists anywhere in the data model today
                  // (no review-aggregation source, by design — see this
                  // screen's earlier editorial-content work) — this line is
                  // just the location, never a fabricated star rating.
                  if (gem.gemLocation != null &&
                      gem.gemLocation!.isNotEmpty) ...[
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
                  const SizedBox(height: 16),

                  _QuickActionRow(
                    canDirections: gem.hasCoords,
                    onDirections:
                        gem.hasCoords ? () => _openDirections(gem) : null,
                    isSaved: isSaved,
                    onToggleSave: gem.isFromPoi
                        ? _comingSoonSave
                        : () => context.read<GemProvider>().toggleSave(gem),
                    onCopyLink: () => _copyLink(gem),
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
                  // A verified business listing for this same place, if one
                  // exists — deliberately NOT folded into the accordion
                  // above: the curated content there is untouched by
                  // whether a business has claimed this place, and this
                  // reads as its own distinct, business-attributed section
                  // rather than editorial content. An Attraction and a
                  // Restaurant can both legitimately link to the same Gem
                  // (see _linkedRestaurant's doc comment), so both cards
                  // can show at once.
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
              ),
            ),
          ),
          if (_nearby.isNotEmpty)
            SliverToBoxAdapter(child: _NearbyExperiences(pois: _nearby)),
          // Clears the sticky bottom CTA below (its own SafeArea already
          // covers the device inset; this just keeps the last scrolled
          // content from ending up flush behind it).
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      bottomNavigationBar: _StickyCta(
        gem: gem,
        activeTrip: tripProv.activeTrip,
        alreadyOnTrip: alreadyOnTrip,
        isSaved: isSaved,
        canDirections: gem.hasCoords,
        onDirections: gem.hasCoords ? () => _openDirections(gem) : null,
        onSave: gem.isFromPoi
            ? _comingSoonSave
            : () => context.read<GemProvider>().toggleSave(gem),
        onAddToTrip: _addToTrip,
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gem.description != null && gem.description!.isNotEmpty) ...[
          Text(gem.description!,
              style: GoogleFonts.fredoka(
                  fontSize: 14, color: AppTheme.lightMute, height: 1.6)),
          const SizedBox(height: 14),
        ],
        if (gem.difficulty != null && gem.difficulty!.isNotEmpty) ...[
          _InfoTile(
              icon: Icons.trending_up_rounded,
              label: 'Difficulty',
              value: gem.difficulty!),
          const SizedBox(height: 10),
        ],
        if (gem.bestTimeToVisit != null && gem.bestTimeToVisit!.isNotEmpty)
          _InfoTile(
              icon: Icons.wb_sunny_outlined,
              label: 'Best Time',
              value: gem.bestTimeToVisit!),
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
  });

  final bool canDirections;
  final VoidCallback? onDirections;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _QuickActionButton(
          icon: Icons.directions_outlined,
          label: 'Directions',
          onTap: onDirections,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QuickActionButton(
          icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
          label: isSaved ? 'Saved' : 'Save',
          onTap: onToggleSave,
          active: isSaved,
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.lightMute)),
          Text(value,
              style:
                  GoogleFonts.fredoka(fontSize: 13, color: AppTheme.lightInk)),
        ]),
      ]),
    );
  }
}

/// Sticky primary CTA, always visible while scrolling (this is the parent
/// Scaffold's `bottomNavigationBar`, not part of the scrollable body) —
/// paired with a small square icon-only Directions button. Primary action:
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

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/layout/max_width_center.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/logic/currency.dart';
import '../../core/logic/booking_itinerary.dart';
import '../../core/logic/trip_insights.dart';
import '../../core/logic/trip_route.dart';
import '../../core/logic/settle_up.dart';
import '../../models/hike.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/gem_provider.dart';
import '../../providers/story_provider.dart';
import '../../providers/splits_provider.dart';
import '../../providers/trip_provider.dart';
import '../../providers/trip_setup_provider.dart';
import '../../models/story.dart';
import '../../models/gem.dart';
import '../../models/trip.dart';
import '../../models/trip_stop.dart';
import '../../models/trip_booking.dart';
import '../../models/trip_traveler.dart';
import '../../models/trip_document.dart';
import '../../models/packing_item.dart';
import '../../widgets/common/app_shell.dart';
import '../../widgets/budget_status.dart';
import '../../widgets/state_views.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/common/add_expense_sheet.dart';
import '../../widgets/common/traveler_lookup_sheet.dart';
import '../trip_map/trip_map_dialog.dart';
import '../trip_setup/edit_trip_sheet.dart';
import '../trip_builder/widgets/add_stop_sheet.dart';
import '../trips/trips_list_screen.dart' show showTripSwitcherSheet;

part 'profile_palette.dart';
part 'widgets/profile_atoms.dart';
part 'widgets/profile_chrome.dart';
part 'tabs/overview_tab.dart';
part 'tabs/trips_tab.dart';
part 'tabs/stories_tab.dart';
part 'tabs/saved_tab.dart';
part 'tabs/badges_tab.dart';
part 'tabs/settings_tab.dart';

/// Deep-link payload for `context.go('/profile', extra: ...)` — lets a caller
/// (currently just Trip Builder's back button) land directly on a tab, and
/// for My Trip specifically, a segment + trip. Closes the standing
/// `TODO(tab-deeplink)` that every builder back-button used to carry.
class ProfileDeepLink {
  const ProfileDeepLink(
      {required this.tab,
      this.tripId,
      this.segment = TripDetailSegment.itinerary});

  final int tab;
  final String? tripId;
  final TripDetailSegment segment;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.deepLink});

  final ProfileDeepLink? deepLink;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Both defaults are overridden from widget.deepLink in initState, below,
  // when the screen is reached via a deep link (e.g. Trip Builder's back
  // button) rather than the tab bar/drawer.
  int _tab =
      0; // 0 Overview · 1 My Trip · 2 Saved Gems · 3 My Stories · 4 Badges · 5 Settings
  // Which My Trip segment to land on next time tab 1 opens — set by
  // Overview's chip taps via _openMyTrip.
  TripDetailSegment _myTripSegment = TripDetailSegment.itinerary;

  bool _statsLoading = false;
  double _spent = 0;
  int _groups = 0;

  // Order matches docs/mockups/travel_planner_profile.html. SETTINGS stays
  // terminal (near-universal convention). Keep this in lockstep with the
  // _body switch.
  static const _tabs = [
    'Overview',
    'My Trip',
    'Saved Gems',
    'My Stories',
    'Badges',
    'Settings',
  ];

  void _openMyTrip(TripDetailSegment segment) => setState(() {
        _tab = 1;
        _myTripSegment = segment;
      });

  @override
  void initState() {
    super.initState();
    final deepLink = widget.deepLink;
    if (deepLink != null) {
      _tab = deepLink.tab;
      _myTripSegment = deepLink.segment;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  // Pull the user's split groups and tally what they've spent across them.
  Future<void> _loadStats() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final uid = auth.user!.id;

    // TripProvider is lazy — nothing loads its trips until the builder's retry
    // button or here. The stats-bar TRIPS count, the next-trip card, and the
    // MY TRIPS tab all read TripProvider.trips, so kick a one-shot load on
    // profile mount. Guarded so a populated cache (e.g. user came back from the
    // builder) isn't refetched. Awaited (not fire-and-forget) so we can resolve
    // the active trip below and fetch its bookings — the ALERTS stat needs both.
    final trips = context.read<TripProvider>();
    if (trips.trips.isEmpty && !trips.isLoading) await trips.init();
    if (!mounted) return;

    // Bookings feed the derived ALERTS stat + Overview pace. Only the active
    // trip's bookings are needed here (the strip reads one trip); fetchForTrip is
    // idempotent/guarded, so a warm cache is a no-op. No active trip → nothing to
    // fetch and the stat renders an em-dash.
    final active = trips.activeTrip;
    if (active != null) {
      context.read<BookingProvider>().fetchForTrip(active.id);
    }

    // Hydrate the Saved Gems tab (and seed heart-toggle state) on mount. Guarded
    // and idempotent inside the provider, so this is a no-op once loaded.
    context.read<GemProvider>().loadSaved();

    // Hydrate the My Stories tab with the owner's OWN submissions (by email,
    // including pending). Distinct from the shell's approved-only `myStories`
    // list below — see the "two lists, two intents" note there. Guarded and
    // idempotent inside the provider (loaded-once unless forced).
    if (auth.user!.email != null) {
      context.read<StoryProvider>().loadMyStories(auth.user!.email!);
    }

    setState(() => _statsLoading = true);
    final splits = context.read<SplitsProvider>();
    try {
      final summary = await splits.fetchSpendSummary(uid);
      if (mounted) {
        setState(() {
          _spent = summary.spent;
          _groups = summary.groups;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) return _SignInPrompt();

    final user = auth.user!;
    // One clock read per frame — every time-relative insight below (alerts, and
    // later Overview pace) shares it so nothing disagrees about "now".
    final now = DateTime.now();

    final gemProvider = context.watch<GemProvider>();
    final gems = gemProvider.allGems.where((g) => g.userId == user.id).toList();
    // Strip SAVED stat: bookmarked gems, not dropped pins. Pre-loadSaved this
    // reads 0 and refines on notify — same accepted transient as ALERTS.
    final savedCount = gemProvider.savedGems.length;

    // Shell's approved-only owner list — feeds the Overview RECENT STORIES card,
    // _memberSince, and the badge count (published-earns, so approved-only is
    // correct here). This is a DIFFERENT list from the My Stories tab's
    // StoryProvider.myStories, which is the by-email owner view including
    // pending. Two lists, two intents — do not collapse them.
    // FOLLOW-UP: this name-fallback OR (`s.authorName == user.name`) shares the
    // collision risk the My Stories query dropped — two users with the same
    // display name cross-match. Consider narrowing to email-only once verified
    // nothing depends on name matching. Left as-is this pass (pre-existing
    // behavior; changing it is outside this step's boundary).
    final myStories = context
        .watch<StoryProvider>()
        .allStories
        .where((s) =>
            (user.email != null && s.email == user.email) ||
            s.authorName == user.name)
        .toList();
    // Real trips owned by this user — feeds the TRIPS stat and the avg-per-trip
    // divisor. Distinct from _groups (split groups), which the "Groups settled"
    // line still uses. Two numbers, two sources; do not collapse.
    // TODO(perf): both this watch and _OverviewTab watch TripProvider — a
    // unified select would be tighter if TripProvider starts notifying often
    // (e.g. realtime collab). Bounded to the profile screen for now.
    final tripProvider = context.watch<TripProvider>();
    final tripCount = tripProvider.tripsCountFor(user.id);

    // Derived ALERTS stat for the active trip. Computed once here (shared `now`)
    // and passed down; null when there's no active trip so the strip shows '–'
    // rather than a misleading 0. Reads the same mappable/committed pipeline the
    // Overview tab will render in full.
    final active = tripProvider.activeTrip;
    List<Alert> alerts = const [];
    TripPace? pace;
    if (active != null) {
      final stops = tripProvider.stopsFor(active.id);
      final bookings = context.watch<BookingProvider>().bookingsFor(active.id);
      final actualByCategory = actualSpendByCategory(
        stops: stops,
        bookings: bookings,
        stopCategory: tripProvider.bucketForStop,
      );
      // One tripAlerts call, two consumers: the strip reads its length (below),
      // the Overview tab renders the list (capped at 4). Same shared `now`.
      alerts = tripAlerts(
        tripId: active.id,
        stops: stops,
        bookings: bookings,
        plannedByCategory: tripProvider.plannedByCategory(active.id),
        actualByCategory: actualByCategory,
        now: now,
      );
      // Pace shares the same `now`/stops/bookings. Signature per the landed
      // trip_insights.dart: totalBudgetVnd + tripStart + tripDays (day count).
      pace = computePace(
        totalBudgetVnd: active.budgetVnd,
        stops: stops,
        bookings: bookings,
        tripStart: active.startDate,
        tripDays: active.endDate.difference(active.startDate).inDays + 1,
        now: now,
      );
    }
    // Strip ALERTS stat: null when no active trip → renders '–'; 0 when there's
    // an active trip with nothing flagged (an honest zero, not a dash).
    final int? alertCount = active == null ? null : alerts.length;

    // Badges — evaluated once in the shell (same one-source pattern as `now` and
    // the alerts count) and passed down as a pure render list. Counts are the
    // lifetime metrics already computed above; bookings is an honest 0 (its two
    // badges render locked) pending the lifetime-count follow-up
    // (project_bookings_badge_followup.md) — never fed the transient per-trip
    // cache, which would be a badge that un-earns when the active trip changes.
    final badges = evaluateBadges(counts: {
      BadgeMetric.gems: savedCount,
      BadgeMetric.trips: tripCount,
      BadgeMetric.stories: myStories.length,
      BadgeMetric.bookings: 0,
    });

    return Scaffold(
      backgroundColor: _kPage,
      body: Column(
        children: [
          Stack(
            children: [
              const _ChromeGlow(),
              Column(
                children: [
                  _Header(
                    user: user,
                    onMenu: () => AppShellScope.of(context).openDrawer(),
                    onSettings: () => setState(() => _tab = 5),
                    onSignOut: () => _confirmSignOut(context),
                    memberSince: _memberSince(gems, myStories),
                  ),
                  _StatsBar(
                    gems: savedCount,
                    trips: tripCount,
                    alerts: alertCount,
                    spent: _spent,
                    loading: _statsLoading,
                  ),
                ],
              ),
            ],
          ),
          _TabBar(
            tabs: _tabs,
            active: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: _body(
                context, myStories, tripCount, badges, alerts, pace, active),
          ),
        ],
      ),
    );
  }

  Widget _body(
      BuildContext context,
      List<Story> stories,
      int tripCount,
      List<BadgeProgress> badges,
      List<Alert> alerts,
      TripPace? pace,
      Trip? active) {
    switch (_tab) {
      case 1:
        return _MyTripTab(
          trip: active,
          initialSegment: _myTripSegment,
          initialTripId: widget.deepLink?.tripId,
        );
      case 2:
        return const _SavedTab();
      case 3:
        return const _StoriesTab();
      case 4:
        return _BadgesTab(badges: badges);
      case 5:
        return _SettingsTab(onSignOut: () => _confirmSignOut(context));
      default:
        return _OverviewTab(
          spent: _spent,
          groups: _groups,
          tripCount: tripCount,
          stories: stories,
          alerts: alerts,
          pace: pace,
          budgetVnd: active?.budgetVnd,
          symbol: currencyFor(active?.currency).symbol,
          badges: badges,
          onOpenTripSegment: _openMyTrip,
          onSwitchTab: (i) => setState(() => _tab = i),
        );
    }
  }

  String? _memberSince(List<Gem> gems, List<Story> stories) {
    final dates = <DateTime>[
      ...gems.map((g) => g.savedAt),
      ...stories.map((s) => s.createdAt),
    ];
    if (dates.isEmpty) return null;
    dates.sort();
    final d = dates.first;
    return 'Member since ${_months[d.month - 1]} ${d.year}';
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Sign Out',
            style: GoogleFonts.bebasNeue(fontSize: 22, color: _kInk)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.fredoka(color: _kMute)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<BookingProvider>().clear();
              context.read<TripSetupProvider>().clear();
              context.read<SplitsProvider>().clear();
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

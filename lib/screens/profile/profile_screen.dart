import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/destination_provider.dart';
import '../../providers/gem_provider.dart';
import '../../providers/story_provider.dart';
import '../../providers/splits_provider.dart';
import '../../providers/trip_provider.dart';
import '../../models/story.dart';
import '../../models/gem.dart';
import '../../models/trip.dart';
import '../../widgets/common/app_shell.dart';
import '../../widgets/budget_status.dart';

// Light palette for the profile surface (the rest of the app is dark, but this
// page intentionally uses a bright "dashboard" look per the redesign).
const _kPage = Color(0xFFFFFFFF);
const _kStripe = Color(0xFFF1ECE4);
const _kCard = Color(0xFFF5F3EF);
const _kBorder = Color(0xFFE7E2D9);
const _kInk = Color(0xFF1A1A1A);
const _kMute = Color(0xFF8A8A8A);
const _kTeal = Color(0xFF12A594);
const _kGreen = Color(0xFF3C9A5F);
const _headerTop = Color(0xFF1A1008);
const _headerBottom = Color(0xFF0F0A05);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0; // 0 Overview · 1 My Stories · 2 Saved Gems · 3 Badges · 4 My Trips · 5 Settings

  bool _statsLoading = false;
  double _spent = 0;
  int _groups = 0;

  // SETTINGS stays terminal (near-universal convention); MY TRIPS, a primary
  // feature, sits ahead of it. Keep this order in lockstep with the _body switch.
  static const _tabs = [
    (Icons.person_outline, 'OVERVIEW'),
    (Icons.menu_book_outlined, 'MY STORIES'),
    (Icons.diamond_outlined, 'SAVED GEMS'),
    (Icons.emoji_events_outlined, 'BADGES'),
    (Icons.map_outlined, 'MY TRIPS'),
    (Icons.settings_outlined, 'SETTINGS'),
  ];

  @override
  void initState() {
    super.initState();
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
    // builder) isn't refetched; fire-and-forget since each surface watches.
    final trips = context.read<TripProvider>();
    if (trips.trips.isEmpty && !trips.isLoading) trips.init();

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
    final gems = context
        .watch<GemProvider>()
        .allGems
        .where((g) => g.userId == user.id)
        .toList();
    final myStories = context
        .watch<StoryProvider>()
        .allStories
        .where((s) =>
            (user.email != null && s.email == user.email) ||
            s.authorName == user.name)
        .toList();
    final saved = context.watch<DestinationProvider>().saved;
    // Real trips owned by this user — feeds the TRIPS stat and the avg-per-trip
    // divisor. Distinct from _groups (split groups), which the "Groups settled"
    // line still uses. Two numbers, two sources; do not collapse.
    // TODO(perf): both this watch and _OverviewTab watch TripProvider — a
    // unified select would be tighter if TripProvider starts notifying often
    // (e.g. realtime collab). Bounded to the profile screen for now.
    final tripCount = context.watch<TripProvider>().tripsCountFor(user.id);

    return Scaffold(
      backgroundColor: _kPage,
      body: Column(
        children: [
          _Header(
            user: user,
            onMenu: () => AppShellScope.of(context).openDrawer(),
            onSettings: () => setState(() => _tab = 5),
            onSignOut: () => _confirmSignOut(context),
            memberSince: _memberSince(gems, myStories),
          ),
          _StatsBar(
            gems: gems.length,
            trips: tripCount,
            friends: 0,
            spent: _spent,
            loading: _statsLoading,
          ),
          _TabBar(
            tabs: _tabs,
            active: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: _body(context, gems, myStories, saved, tripCount),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<Gem> gems, List<Story> stories,
      List saved, int tripCount) {
    switch (_tab) {
      case 1:
        return _StoriesTab(stories: stories);
      case 2:
        return _SavedTab(saved: saved);
      case 3:
        return const _BadgesTab();
      case 4:
        return const _TripsTab();
      case 5:
        return _SettingsTab(onSignOut: () => _confirmSignOut(context));
      default:
        return _OverviewTab(
          spent: _spent,
          groups: _groups,
          tripCount: tripCount,
          stories: stories,
          gems: gems,
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
            style: GoogleFonts.dmSans(color: _kMute)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────
class _Header extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final String? memberSince;
  const _Header({
    required this.user,
    required this.onMenu,
    required this.onSettings,
    required this.onSignOut,
    required this.memberSince,
  });

  String get _handle {
    if (user.email != null && user.email!.contains('@')) {
      return '@${user.email!.split('@').first}';
    }
    return '@${user.name.toLowerCase().replaceAll(RegExp(r"\s+"), '.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_headerTop, _headerBottom],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Menu button
              GestureDetector(
                onTap: onMenu,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.menu, color: Color(0xFF1A1A1A)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(user: user),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.bebasNeue(
                                    fontSize: 32,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.7)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          if (memberSince != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              memberSince!,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: onSettings,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Icon(Icons.settings_outlined,
                              size: 20, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: onSignOut,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.red.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.logout,
                                  size: 15, color: Color(0xFFFF6B6B)),
                              const SizedBox(width: 6),
                              Text(
                                'Out',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF6B6B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AuthUser user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6B4A2F), width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: user.avatarUrl != null
                ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                : Container(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    child: Center(
                      child: Text(
                        user.name.isNotEmpty
                            ? user.name[0].toUpperCase()
                            : 'E',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 40, color: AppTheme.primary),
                      ),
                    ),
                  ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(color: _headerBottom, width: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final int gems, trips, friends;
  final double spent;
  final bool loading;
  const _StatsBar({
    required this.gems,
    required this.trips,
    required this.friends,
    required this.spent,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kStripe,
      child: Row(
        children: [
          _cell('$gems', 'GEMS', AppTheme.primary),
          _divider(),
          _cell('$trips', 'TRIPS', _kInk),
          _divider(),
          _cell('$friends', 'FRIENDS', _kInk),
          _divider(),
          _cell(loading ? '··' : '\$${spent.toStringAsFixed(0)}', 'SPENT',
              _kTeal),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 44, color: _kBorder);

  Widget _cell(String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.bebasNeue(
                    fontSize: 30, color: color, height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: _kMute, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// TAB BAR
// ─────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final List<(IconData, String)> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  const _TabBar(
      {required this.tabs, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final i = e.key;
            final isActive = i == active;
            final color = isActive ? AppTheme.primary : _kMute;
            return GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppTheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(e.value.$1, size: 20, color: color),
                    const SizedBox(height: 5),
                    Text(
                      e.value.$2,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final double spent;
  final int groups;    // split groups → "Groups settled"
  final int tripCount; // real trips → avg-per-trip divisor
  final List<Story> stories;
  final List<Gem> gems;
  const _OverviewTab({
    required this.spent,
    required this.groups,
    required this.tripCount,
    required this.stories,
    required this.gems,
  });

  @override
  Widget build(BuildContext context) {
    final avg = tripCount > 0 ? spent / tripCount : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        // Next / upcoming trip pulse — first thing a returning user sees.
        const _NextTripCard(),
        const SizedBox(height: 16),

        // Expense summary
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.trending_up, label: 'EXPENSE SUMMARY', color: _kTeal),
              const SizedBox(height: 16),
              _summaryRow('Total across all trips',
                  '\$${spent.toStringAsFixed(1)}', _kInk),
              const SizedBox(height: 14),
              _summaryRow('Average per trip',
                  '\$${avg.toStringAsFixed(2)}', _kInk),
              const SizedBox(height: 14),
              _summaryRow('Groups settled', '$groups / $groups', _kTeal),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  value: 1,
                  minHeight: 5,
                  backgroundColor: _kBorder,
                  valueColor: AlwaysStoppedAnimation(_kTeal),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Recent stories
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.menu_book_outlined,
                  label: 'RECENT STORIES',
                  color: AppTheme.primary),
              const SizedBox(height: 8),
              if (stories.isEmpty)
                _emptyLine('You haven\'t submitted any stories yet.')
              else
                ...stories.take(3).toList().asMap().entries.map((e) =>
                    _StoryRow(story: e.value, divider: e.key > 0)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Saved / my gems
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                  icon: Icons.diamond_outlined,
                  label: 'MY GEMS',
                  color: AppTheme.primary),
              const SizedBox(height: 8),
              if (gems.isEmpty)
                _emptyLine('Drop your first gem from the map.')
              else
                ...gems.take(3).toList().asMap().entries.map((e) =>
                    _GemRow(gem: e.value, divider: e.key > 0)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF555555))),
        ),
        Text(value,
            style: GoogleFonts.dmSans(
                fontSize: 17, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text,
            style: GoogleFonts.dmSans(fontSize: 13, color: _kMute)),
      );
}

// ─────────────────────────────────────────
// NEXT TRIP CARD (Overview)
// ─────────────────────────────────────────
/// Overview's trip pulse. Three states, one widget — the two *empty* states
/// carry different copy on purpose: a user with past trips must not be told to
/// "plan your first". Compact by design (Overview stacks cards below it); the
/// full-width create CTA lives on the MY TRIPS tab, not here.
class _NextTripCard extends StatelessWidget {
  const _NextTripCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final active = provider.activeTrip; // soonest trip within 30 days, or null
    final hasHistory = provider.trips.isNotEmpty;

    // State A — no upcoming trip AND no trips ever: first-run nudge + chip CTA.
    if (active == null && !hasHistory) {
      return _NextTripShell(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No trips yet',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kInk)),
                  const SizedBox(height: 2),
                  Text('Plan your first adventure.',
                      style:
                          GoogleFonts.dmSans(fontSize: 13, color: _kMute)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _TripChipCta(
                label: '+ New trip', onTap: () => context.go('/trips/new')),
          ],
        ),
      );
    }

    // State B — trips exist but none upcoming: past-trips nudge. Whole card is
    // tappable; a right-side chevron (matching State C) carries the affordance
    // so B and C read as one widget in two data modes.
    if (active == null) {
      return GestureDetector(
        onTap: () => context.go('/trips/new'),
        behavior: HitTestBehavior.opaque,
        child: _NextTripShell(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No trips coming up',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _kInk)),
                    const SizedBox(height: 2),
                    Text('Plan your next trip',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: _kMute),
            ],
          ),
        ),
      );
    }

    // State C — populated: identity + mini budget bar (fraction only; the
    // category breakdown lives in the builder, not here).
    final spent = provider.totalSpent(active.id);
    final status = BudgetStatus.of(spent: spent, budgetVnd: active.budgetVnd);
    final fill = (status.pct / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => context.go('/trips/${active.id}'),
      behavior: HitTestBehavior.opaque,
      child: _NextTripShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.luggage,
                      size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(active.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _kInk)),
                      const SizedBox(height: 2),
                      Text(
                        Trip.formatDateRange(active.startDate, active.endDate),
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 11, color: _kMute, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: _kMute),
              ],
            ),
            const SizedBox(height: 12),
            // Mini budget bar — same accent state machine as the sidebar.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: _kBorder),
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(height: 6, color: status.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '₫${Trip.formatVnd(spent, short: true)} of '
              '₫${Trip.formatVnd(active.budgetVnd, short: true)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: _kMute, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card chrome shared by all three [_NextTripCard] states — same fill /
/// border / radius as [_Card] but tuned padding for the denser trip content.
class _NextTripShell extends StatelessWidget {
  final Widget child;
  const _NextTripShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

/// Small pill CTA used by [_NextTripCard]'s first-run state.
class _TripChipCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TripChipCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

// ─────────────────────────────────────────
// MY TRIPS TAB
// ─────────────────────────────────────────
/// Full trip list, bucketed by proximity. Uses the same daysUntilStart split
/// as [TripProvider.activeTrip]: 0–30 days is "soon", beyond that "upcoming",
/// negative is "past". Rows rhyme with [_GemRow]; sections use [_CardHeader].
class _TripsTab extends StatelessWidget {
  const _TripsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final all = provider.trips; // provider sorts soonest startDate first

    if (all.isEmpty) {
      return _EmptyState(
        icon: Icons.map_outlined,
        title: 'No trips yet',
        subtitle: 'Plan your first and it\'ll show up here.',
        cta: 'Create a trip',
        onTap: () => context.go('/trips/new'),
      );
    }

    final soon = <Trip>[], upcoming = <Trip>[], past = <Trip>[];
    for (final t in all) {
      if (t.daysUntilStart < 0) {
        past.add(t);
      } else if (t.isUpcoming) {
        soon.add(t);
      } else {
        upcoming.add(t);
      }
    }
    // soon/upcoming inherit soonest-first order; past reads most-recent first.
    past.sort((a, b) => b.startDate.compareTo(a.startDate));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _CreateTripButton(onTap: () => context.go('/trips/new')),
        const SizedBox(height: 16),
        ..._section('ACTIVE · SOON', soon, provider),
        ..._section('UPCOMING', upcoming, provider),
        ..._section('PAST', past, provider),
      ],
    );
  }

  // Section = _CardHeader + a _Card of _TripRow siblings. Empty groups skipped,
  // so the gaps land only where there's content.
  List<Widget> _section(String label, List<Trip> trips, TripProvider p) {
    if (trips.isEmpty) return const [];
    return [
      _CardHeader(
          icon: Icons.map_outlined, label: label, color: AppTheme.primary),
      const SizedBox(height: 8),
      _Card(
        child: Column(
          children: [
            for (final (i, t) in trips.indexed)
              _TripRow(trip: t, divider: i > 0, spent: p.totalSpent(t.id)),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}

/// One trip in the MY TRIPS list — the [_GemRow] idiom (tinted leading tile,
/// name + subtitle, trailing accent) with a budget-pct pill instead of a
/// chevron. Taps into the trip summary.
class _TripRow extends StatelessWidget {
  final Trip trip;
  final bool divider;
  final int spent;
  const _TripRow(
      {required this.trip, required this.divider, required this.spent});

  @override
  Widget build(BuildContext context) {
    final status = BudgetStatus.of(spent: spent, budgetVnd: trip.budgetVnd);
    final pct = status.pct.round();
    return GestureDetector(
      onTap: () => context.go('/trips/${trip.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: _kBorder))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.map_outlined,
                  size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Trip.formatDateRange(trip.startDate, trip.endDate)
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: _kMute, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Budget-pct pill. Only meaningful once a budget is set; unset
            // budgets read as 0% so the pill stays honest rather than blank.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: status.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: status.accent.withValues(alpha: 0.5)),
              ),
              child: Text('$pct%',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: status.accent,
                      letterSpacing: 0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width primary CTA atop the MY TRIPS list.
class _CreateTripButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateTripButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text('Create new trip',
                style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// MY STORIES TAB
// ─────────────────────────────────────────
class _StoriesTab extends StatelessWidget {
  final List<Story> stories;
  const _StoriesTab({required this.stories});

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No stories yet',
        subtitle: 'Share your first adventure with the tribe.',
        cta: 'Submit a story',
        onTap: () => context.go('/submit-story'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _Card(
          child: Column(
            children: stories
                .asMap()
                .entries
                .map((e) => _StoryRow(story: e.value, divider: e.key > 0))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// SAVED GEMS TAB
// ─────────────────────────────────────────
class _SavedTab extends StatelessWidget {
  final List saved;
  const _SavedTab({required this.saved});

  @override
  Widget build(BuildContext context) {
    if (saved.isEmpty) {
      return _EmptyState(
        icon: Icons.diamond_outlined,
        title: 'Nothing saved yet',
        subtitle: 'Bookmark spots and they\'ll show up here.',
        cta: 'Explore the map',
        onTap: () => context.go('/explore'),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: saved.map<Widget>((d) {
        return GestureDetector(
          onTap: () => context.go('/listings/${d.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(d.imageUrl, fit: BoxFit.cover),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    d.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────
// BADGES TAB
// ─────────────────────────────────────────
class _BadgesTab extends StatelessWidget {
  const _BadgesTab();
  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.emoji_events_outlined,
      title: 'No badges yet',
      subtitle: 'Earn badges by dropping gems, logging trips and sharing stories.',
    );
  }
}

// ─────────────────────────────────────────
// SETTINGS TAB
// ─────────────────────────────────────────
class _SettingsTab extends StatelessWidget {
  final VoidCallback onSignOut;
  const _SettingsTab({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      children: [
        _Card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _settingRow(Icons.person_outline, 'Edit profile', () {}),
              _settingRow(Icons.notifications_outlined, 'Notifications', () {}),
              _settingRow(Icons.lock_outline, 'Privacy', () {}),
              _settingRow(Icons.receipt_long_outlined, 'Expense Splits',
                  () => context.go('/splits')),
              _settingRow(Icons.help_outline, 'Help & support', () {}),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onSignOut,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, size: 18, color: Colors.red),
                const SizedBox(width: 8),
                Text('Sign Out',
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingRow(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _kInk),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _kMute),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// SHARED PIECES
// ─────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CardHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _StoryRow extends StatelessWidget {
  final Story story;
  final bool divider;
  const _StoryRow({required this.story, required this.divider});

  @override
  Widget build(BuildContext context) {
    final approved = story.status.toLowerCase() == 'approved';
    final pending = story.status.toLowerCase() == 'pending';
    final pillColor = approved
        ? _kGreen
        : pending
            ? const Color(0xFFB8860B)
            : _kMute;
    return GestureDetector(
      onTap: () => context.go('/stories/${story.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: _kBorder))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w800, color: _kInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (story.location ?? 'UNKNOWN').toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: _kMute, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: pillColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pillColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(approved ? Icons.check : Icons.schedule,
                      size: 12, color: pillColor),
                  const SizedBox(width: 4),
                  Text(
                    story.status.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: pillColor,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GemRow extends StatelessWidget {
  final Gem gem;
  final bool divider;
  const _GemRow({required this.gem, required this.divider});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/gems/${gem.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: _kBorder))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.place,
                  size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gem.gemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w800, color: _kInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (gem.gemLocation ?? gem.displayCategory).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: _kMute, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _kMute),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onTap;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.cta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: _kBorder),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.bebasNeue(fontSize: 26, color: _kInk)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: _kMute, height: 1.5)),
            if (cta != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(cta!,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🧗', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              Text('JOIN THE TRIBE',
                  style: GoogleFonts.bebasNeue(
                      fontSize: 32,
                      color: AppTheme.textPrimary,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your profile, save gems, track hikes, and connect with fellow adventurers.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/auth?redirect=/profile'),
                  child: const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

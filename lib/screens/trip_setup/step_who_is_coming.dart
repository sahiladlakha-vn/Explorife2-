import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/common/traveler_lookup_sheet.dart';
import '../../widgets/app_network_image.dart';

/// Setup Step 2 of 3 — "Who's coming?", between trip details (Step 1) and the
/// Fresh/Blueprint template choice (Step 3). Placed here rather than last:
/// who's coming is part of *defining* the trip (same footing as budget or
/// vibe), while the template choice is a mechanical "how do I want the
/// itinerary seeded" decision that reads better as the final step right
/// before creation.
///
/// Always valid — this step is entirely skippable, so [isValid] never blocks
/// Continue. The organizer (current user) is shown fixed/non-removable;
/// added travelers live in [TripDraft.pendingTravelers] until createTrip
/// turns them into real trip_collaborators rows. Presentational, same
/// contract as StepOneInit/StepTwoTemplate: mutates [draft] and calls
/// [onChanged] rather than holding its own state.
class StepWhoIsComing extends StatelessWidget {
  const StepWhoIsComing({
    super.key,
    required this.draft,
    required this.scrollController,
    required this.onChanged,
  });

  final TripDraft draft;
  final ScrollController scrollController;
  final VoidCallback onChanged;

  static bool isValid(TripDraft d) => true;

  void _openLookup(BuildContext context) {
    final me = context.read<AuthProvider>().user;
    final excludeIds = {
      if (me != null) me.id,
      for (final t in draft.pendingTravelers) t.userId,
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TravelerLookupSheet(
        excludeUserIds: excludeIds,
        onSelect: (profile) {
          draft.pendingTravelers = [
            ...draft.pendingTravelers,
            PendingTraveler(
              userId: profile.id,
              displayName: profile.displayName,
              avatarUrl: profile.avatarUrl,
            ),
          ];
          onChanged();
        },
      ),
    );
  }

  void _remove(PendingTraveler t) {
    draft.pendingTravelers =
        draft.pendingTravelers.where((p) => p.userId != t.userId).toList();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Who\'s coming?',
            style: TextStyle(
                color: AppTheme.lightInk,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            "Add travelers now, or skip — you can invite people from the Trip tab later too.",
            style: TextStyle(color: AppTheme.lightMute, fontSize: 12.5, height: 1.3)),
        const SizedBox(height: 16),
        if (me != null)
          _TravelerTile(
            name: me.name,
            avatarUrl: me.avatarUrl,
            roleLabel: 'Organizer',
            removable: false,
          ),
        for (final t in draft.pendingTravelers) ...[
          const SizedBox(height: 8),
          _TravelerTile(
            name: t.displayName,
            avatarUrl: t.avatarUrl,
            roleLabel: 'Member',
            removable: true,
            onRemove: () => _remove(t),
          ),
        ],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _openLookup(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.lightBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('+ Add a traveler',
                style: TextStyle(
                    color: AppTheme.lightMute,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _TravelerTile extends StatelessWidget {
  const _TravelerTile({
    required this.name,
    required this.avatarUrl,
    required this.roleLabel,
    required this.removable,
    this.onRemove,
  });

  final String name;
  final String? avatarUrl;
  final String roleLabel;
  final bool removable;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          ClipOval(
            child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                ? AppNetworkImage(url: avatarUrl!, width: 36, height: 36)
                : Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    child: Text(initials,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.lightInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text(roleLabel,
                    style:
                        const TextStyle(color: AppTheme.lightMute, fontSize: 11)),
              ],
            ),
          ),
          if (removable)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 18, color: AppTheme.lightMute),
            ),
        ],
      ),
    );
  }
}

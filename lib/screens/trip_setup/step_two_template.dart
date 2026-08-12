import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_blueprint.dart';

/// Setup Step 2 — start Fresh (empty canvas) or seed from a community Blueprint.
/// Presentational: mutates [draft].templateChoice / .blueprintId and calls
/// [onChanged]. Blueprints + loading flag are passed down (parent reads the
/// provider); the empty state is gated behind [isLoading] to survive cold start.
/// Light colorway, matching Profile.
class StepTwoTemplate extends StatelessWidget {
  const StepTwoTemplate({
    super.key,
    required this.draft,
    required this.blueprints,
    required this.isLoading,
    required this.scrollController,
    required this.onChanged,
  });

  final TripDraft draft;
  final List<TripBlueprint> blueprints;
  final bool isLoading;
  final ScrollController scrollController;
  final VoidCallback onChanged;

  /// 'fresh' is always valid; 'blueprint' requires a chosen blueprintId.
  static bool isValid(TripDraft d) =>
      d.templateChoice == 'fresh' ||
      (d.templateChoice == 'blueprint' && d.blueprintId != null);

  @override
  Widget build(BuildContext context) {
    final blueprintDisabled = blueprints.isEmpty && !isLoading;
    final showBlueprintList = draft.templateChoice == 'blueprint';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _ChoiceCard(
          icon: Icons.auto_awesome,
          title: 'Start fresh',
          subtitle: 'A blank canvas — build your days from scratch.',
          selected: draft.templateChoice == 'fresh',
          onTap: () {
            draft.templateChoice = 'fresh';
            draft.blueprintId = null;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          icon: Icons.map_outlined,
          title: 'Use a blueprint',
          subtitle: blueprintDisabled
              ? 'No community blueprints for ${draft.location ?? 'here'} yet.'
              : 'Seed your trip from a curated itinerary.',
          selected: draft.templateChoice == 'blueprint',
          enabled: !blueprintDisabled,
          onTap: () {
            draft.templateChoice = 'blueprint';
            onChanged();
          },
        ),
        if (showBlueprintList) ...[
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              ),
            )
          else if (blueprints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No community blueprints for ${draft.location ?? 'this place'} yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.lightMute, fontSize: 13),
                ),
              ),
            )
          else
            ...blueprints.map((b) => _BlueprintRow(
                  blueprint: b,
                  selected: draft.blueprintId == b.id,
                  onTap: () {
                    draft.blueprintId = b.id;
                    onChanged();
                  },
                )),
        ],
      ],
    );
  }
}

/// The Fresh / Blueprint selector cards (one-of).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primarySoft : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.lightBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppTheme.primary : AppTheme.lightMute, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.lightInk,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 12, height: 1.3)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: AppTheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// One blueprint option (one-of); `meta` is rendered verbatim as editorial copy.
class _BlueprintRow extends StatelessWidget {
  const _BlueprintRow({
    required this.blueprint,
    required this.selected,
    required this.onTap,
  });

  final TripBlueprint blueprint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primarySoft : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.lightBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(blueprint.title,
                        style: const TextStyle(
                            color: AppTheme.lightInk,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      blueprint.meta ??
                          '${blueprint.nights} days · ${blueprint.itemCount} stops',
                      style: const TextStyle(color: AppTheme.lightMute, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: AppTheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

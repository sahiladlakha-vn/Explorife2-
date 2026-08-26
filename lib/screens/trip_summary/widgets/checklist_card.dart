import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/trip_checklist_item.dart';
import '../../../providers/trip_provider.dart';

/// Pre-trip checklist card for the Trip Summary.
///
/// Reads the already section-sorted items from [TripProvider.checklistFor],
/// groups them into collapsible sections (each with a progress bar), and toggles
/// items in place. This selects a `List`, so it rebuilds on every checklist
/// notify — that's expected and correct: this card IS the checklist's
/// interaction surface, so a rebuild per toggle is exactly the scope we want.
class ChecklistCard extends StatelessWidget {
  const ChecklistCard({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final items = context.select<TripProvider, List<TripChecklistItem>>(
      (p) => p.checklistFor(tripId),
    );

    // Group the flat, pre-sorted list by section. Insertion order within each
    // bucket is preserved (already section→sortOrder ordered upstream).
    final bySection = <String, List<TripChecklistItem>>{};
    for (final i in items) {
      (bySection[i.section] ??= []).add(i);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checklist',
            style: TextStyle(
              color: AppTheme.lightInk,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No checklist for this trip yet.',
                style: TextStyle(color: AppTheme.lightMute, fontSize: 12),
              ),
            )
          else
            for (final section in TripChecklistItem.sectionOrder)
              if (bySection[section] != null)
                _ChecklistSection(
                  section: section,
                  items: bySection[section]!,
                ),
        ],
      ),
    );
  }
}

class _ChecklistSection extends StatelessWidget {
  const _ChecklistSection({required this.section, required this.items});

  final String section;
  final List<TripChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final done = items.where((i) => i.isChecked).length;
    final total = items.length;
    final ratio = total == 0 ? 0.0 : done / total;

    return Theme(
      // Strip ExpansionTile's default dividers so it sits cleanly in the card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: done < total, // open sections with work remaining
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                TripChecklistItem.sectionLabel(section),
                style: const TextStyle(
                  color: AppTheme.lightInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$done/$total',
              style: const TextStyle(
                color: AppTheme.lightMute,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: AppTheme.lightBorder,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
        ),
        children: [
          for (final item in items) _ChecklistRow(item: item),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item});

  final TripChecklistItem item;

  Future<void> _toggle(BuildContext context) async {
    // Read the provider synchronously before the await so we don't touch
    // `context` across the async gap.
    final trips = context.read<TripProvider>();
    try {
      await trips.toggleChecklistItem(item.id);
    } catch (_) {
      // TODO(snackbar): surface the toggle failure once the Summary has a
      // ScaffoldMessenger in scope. The provider has already rolled the
      // optimistic flip back and set `error`, so the UI stays consistent.
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _toggle(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              item.isChecked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: item.isChecked ? AppTheme.primary : AppTheme.lightMute,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  color: item.isChecked
                      ? AppTheme.lightMute
                      : AppTheme.lightInk,
                  fontSize: 13,
                  decoration:
                      item.isChecked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

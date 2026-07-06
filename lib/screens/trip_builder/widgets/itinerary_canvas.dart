import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../widgets/app_network_image.dart';
import '../asset_data.dart';

/// Center pane of the Trip Builder: a day chip strip + the active day's card,
/// whose three [TimeSlotBlock]s are `DragTarget<AssetData>`s that receive gems
/// dragged from the DiscoveryPanel. One active day is shown at a time (the
/// shell owns [activeDay]); the sidebar's route map reads the same single day.
///
/// Gem resolution is centralized here: one `watch<GemProvider>()` builds a
/// lookup closure threaded down to every card, so a catalogue refresh rebuilds
/// the subtree once (not once per card) and a deleted gem resolves to null in
/// exactly one place.
class ItineraryCanvas extends StatelessWidget {
  const ItineraryCanvas({
    super.key,
    required this.tripId,
    required this.activeDay,
    required this.onDayChanged,
  });

  final String tripId;
  final int activeDay;
  final ValueChanged<int> onDayChanged;

  @override
  Widget build(BuildContext context) {
    final trip = context.select<TripProvider, Trip?>((p) => p.activeTrip);
    if (trip == null) {
      return const _CanvasMessage('This trip isn\'t loaded.');
    }

    // Jul 12–18 → 6 nights → 7 droppable days (the last is departure day: real
    // trips have breakfast + checkout + a taxi before the flight).
    final dayCount = trip.nights + 1;
    if (dayCount < 1) {
      // Unreachable if Step 1's date validation held — scream in logs so a
      // regression (or a bad DB row) surfaces during development.
      debugPrint(
          'TripBuilder: invalid dates on trip ${trip.id}: ${trip.startDate}–${trip.endDate}');
      return const _CanvasMessage('Invalid trip dates.');
    }

    // One subscription for the whole subtree. The closure is the single point
    // where a missing gem (deleted from the catalogue) becomes null.
    final gems = context.watch<GemProvider>().allGems;
    Gem? resolveGem(String id) =>
        gems.cast<Gem?>().firstWhere((g) => g?.id == id, orElse: () => null);

    // Clamp defensively — a stale activeDay (e.g. dates edited shorter) must not
    // index past the strip.
    final safeDay = activeDay.clamp(1, dayCount);
    final date = trip.startDate.add(Duration(days: safeDay - 1));

    return Container(
      color: AppTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayChipStrip(
            activeDay: safeDay,
            dayCount: dayCount,
            onDayChanged: onDayChanged,
          ),
          const Divider(height: 1, color: AppTheme.divider),
          Expanded(
            child: DayCard(
              tripId: tripId,
              day: safeDay,
              date: date,
              isDeparture: safeDay == dayCount,
              resolveGem: resolveGem,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Day chip strip -------------------------------------------------------

/// Horizontal day selector. One chip per day; the active one is filled. The
/// last day is flagged with a departure glyph so it reads distinctly.
class _DayChipStrip extends StatelessWidget {
  const _DayChipStrip({
    required this.activeDay,
    required this.dayCount,
    required this.onDayChanged,
  });

  final int activeDay;
  final int dayCount;
  final ValueChanged<int> onDayChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: dayCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final day = i + 1;
          final selected = day == activeDay;
          final isDeparture = day == dayCount;
          return GestureDetector(
            onTap: () => onDayChanged(day),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : AppTheme.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.divider),
              ),
              child: Row(
                children: [
                  Text('Day $day',
                      style: TextStyle(
                          color:
                              selected ? Colors.white : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  if (isDeparture) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.flight_takeoff,
                        size: 14,
                        color: selected
                            ? Colors.white
                            : AppTheme.textSecondary),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Day card -------------------------------------------------------------

/// The active day: a header (date + departure tag + day total) over the three
/// fixed time slots. Slots live in a scroll view so a heavy day never clips.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.tripId,
    required this.day,
    required this.date,
    required this.isDeparture,
    required this.resolveGem,
  });

  final String tripId;
  final int day;
  final DateTime date;
  final bool isDeparture;
  final Gem? Function(String gemId) resolveGem;

  static const _slots = ['morning', 'afternoon', 'evening'];

  @override
  Widget build(BuildContext context) {
    final dayTotal =
        context.select<TripProvider, int>((p) => p.dayTotal(tripId, day));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Day $day',
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      if (isDeparture) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: const Text('Departure',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_dateLabel(date),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            _DayTotalPill(totalVnd: dayTotal),
          ],
        ),
        const SizedBox(height: 16),
        for (final slot in _slots) ...[
          TimeSlotBlock(
            tripId: tripId,
            day: day,
            slot: slot,
            resolveGem: resolveGem,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Compact day-spend chip. Free gems keep this at ₫0 until prices are set.
class _DayTotalPill extends StatelessWidget {
  const _DayTotalPill({required this.totalVnd});

  final int totalVnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Text('₫${Trip.formatVnd(totalVnd, short: true)}',
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
    );
  }
}

// --- Time slot (the drop target) -----------------------------------------

/// One time slot of one day: the `DragTarget<AssetData>` that accepts gems.
/// Slot is temporal, not typological — every gem is welcome (always-accept),
/// so the only drop feedback is a hover highlight.
class TimeSlotBlock extends StatelessWidget {
  const TimeSlotBlock({
    super.key,
    required this.tripId,
    required this.day,
    required this.slot, // 'morning' | 'afternoon' | 'evening'
    required this.resolveGem,
  });

  final String tripId;
  final int day;
  final String slot;
  final Gem? Function(String gemId) resolveGem;

  @override
  Widget build(BuildContext context) {
    // TODO(perf): stopsForDay returns a new List each call, so this select
    // fires on every provider notification regardless of whether this day
    // changed. Negligible at ≤5 stops; cache the day's list on the provider
    // if a trip ever grows to dozens of stops.
    final stops = context
        .select<TripProvider, List<TripStop>>((p) => p.stopsForDay(tripId, day))
        .where((s) => s.slot == slot)
        .toList();

    return DragTarget<AssetData>(
      onWillAcceptWithDetails: (_) => true, // always-accept: slot is temporal
      onAcceptWithDetails: (details) {
        HapticFeedback.mediumImpact(); // collision haptic > pickup haptic
        // Gems are free → price 0 at drop; the user sets it via the pill.
        // Fire-and-forget: addStop is optimistic and self-rolls-back on error.
        context.read<TripProvider>().addStop(
              tripId: tripId,
              day: day,
              slot: slot,
              gemId: details.data.gemId,
              priceVnd: 0,
            );
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hovering ? AppTheme.primarySoft : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? AppTheme.primary : AppTheme.divider,
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SlotHeader(
                slot: slot,
                onAddCustom: () => _openCustomSheet(context),
              ),
              if (stops.isEmpty)
                _SlotPlaceholder(hovering: hovering)
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      for (final s in stops)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ItineraryItemCard(
                            stop: s,
                            gem: s.isCustom ? null : resolveGem(s.gemId!),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openCustomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomItemSheet(tripId: tripId, day: day, slot: slot),
    );
  }
}

/// Slot label + "+ Custom" affordance. Lives inside the drop target so hovering
/// highlights the whole region including the label — what a user expects.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.slot, required this.onAddCustom});

  final String slot;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _slotMeta(slot);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          const Spacer(),
          // TODO(desktop): drag-through button ambiguity if we ever add
          // drag-to-scroll — a pointer-down here is unambiguously a tap today.
          TextButton.icon(
            onPressed: onAddCustom,
            icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
            label: const Text('Custom',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-slot hint. Brightens on hover to reinforce "yes, drop here".
class _SlotPlaceholder extends StatelessWidget {
  const _SlotPlaceholder({required this.hovering});

  final bool hovering;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Text(
        hovering ? 'Release to add' : 'Drag a gem here',
        style: TextStyle(
          color: hovering ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// --- Itinerary item card --------------------------------------------------

/// A placed stop. Three render branches: a resolved gem, a custom entry, or an
/// orphaned gem stop (gem deleted from the catalogue) — the last keeps its
/// persisted price and its edit/remove affordances rather than auto-deleting.
// TODO(reorder): drops are append-only — this card is a passive tile. To allow
// dragging a placed stop within a slot or between slots, make it a
// Draggable<...> source (a DragTarget already lives in TimeSlotBlock) and add
// reorderStop / moveStopBetweenSlots to TripProvider with sortOrder recompute.
class ItineraryItemCard extends StatelessWidget {
  const ItineraryItemCard({super.key, required this.stop, required this.gem});

  final TripStop stop;
  final Gem? gem;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _titleFor();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          _Thumb(stop: stop, gem: gem),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PriceEditPill(
            priceVnd: stop.priceVnd,
            onChanged: (v) =>
                context.read<TripProvider>().updateStopPrice(stop.id, v),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<TripProvider>().removeStop(stop.id);
            },
            icon: const Icon(Icons.close,
                size: 18, color: AppTheme.textSecondary),
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  (String, String) _titleFor() {
    if (stop.isCustom) {
      return (stop.customTitle ?? 'Custom stop', 'Custom');
    }
    if (gem == null) {
      return ('Gem unavailable', 'Removed from catalogue');
    }
    return (gem!.gemName, '${gem!.emoji} ${gem!.displayCategory}');
  }
}

/// 40px leading tile: gem photo, emoji fallback, custom glyph, or an
/// "unavailable" icon for an orphaned stop.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.stop, required this.gem});

  final TripStop stop;
  final Gem? gem;

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (stop.isCustom) {
      inner = const Icon(Icons.edit_note, color: AppTheme.textSecondary);
    } else if (gem == null) {
      inner = const Icon(Icons.help_outline,
          color: AppTheme.textSecondary, size: 20);
    } else if (gem!.photoUrl != null && gem!.photoUrl!.isNotEmpty) {
      inner = AppNetworkImage(url: gem!.photoUrl!);
    } else {
      inner = Center(
          child: Text(gem!.emoji, style: const TextStyle(fontSize: 18)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        color: AppTheme.surface,
        child: inner,
      ),
    );
  }
}

/// Inline price editor. Tap the pill to swap it for a compact number field;
/// commit on submit or on tapping away. Shows "Set price" while a stop is free.
class PriceEditPill extends StatefulWidget {
  const PriceEditPill(
      {super.key, required this.priceVnd, required this.onChanged});

  final int priceVnd;
  final ValueChanged<int> onChanged;

  @override
  State<PriceEditPill> createState() => _PriceEditPillState();
}

class _PriceEditPillState extends State<PriceEditPill> {
  final _ctrl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    _ctrl.text = widget.priceVnd == 0 ? '' : widget.priceVnd.toString();
    setState(() => _editing = true);
  }

  void _commit() {
    if (!_editing) return; // guard double-fire (onSubmitted + onTapOutside)
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final v = int.tryParse(digits) ?? 0;
    if (v != widget.priceVnd) widget.onChanged(v);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 92,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.end,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
          decoration: InputDecoration(
            isDense: true,
            prefixText: '₫',
            prefixStyle:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            filled: true,
            fillColor: AppTheme.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
      );
    }

    final free = widget.priceVnd == 0;
    return GestureDetector(
      onTap: _start,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: free ? Colors.transparent : AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: free ? AppTheme.divider : AppTheme.primary),
        ),
        child: Text(
          free
              ? 'Set price'
              : '₫${Trip.formatVnd(widget.priceVnd, short: true)}',
          style: TextStyle(
              color: free ? AppTheme.textSecondary : AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// --- Custom item sheet ----------------------------------------------------

/// Quick-capture sheet for a freeform stop (title + optional price). Mirrors the
/// app's canonical sheet chrome (28px top radius, handle) for consistency with
/// TripSetupSheet. Adds via the same optimistic addStop path as a drop.
class _CustomItemSheet extends StatefulWidget {
  const _CustomItemSheet({
    required this.tripId,
    required this.day,
    required this.slot,
  });

  final String tripId;
  final int day;
  final String slot;

  @override
  State<_CustomItemSheet> createState() => _CustomItemSheetState();
}

class _CustomItemSheetState extends State<_CustomItemSheet> {
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  bool get _canAdd => _titleCtrl.text.trim().isNotEmpty;

  void _add() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final digits = _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final price = int.tryParse(digits) ?? 0;
    HapticFeedback.mediumImpact();
    context.read<TripProvider>().addStop(
          tripId: widget.tripId,
          day: widget.day,
          slot: widget.slot,
          customPayload: {'title': title},
          priceVnd: price,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final (label, _) = _slotMeta(widget.slot);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add custom stop · Day ${widget.day} $label',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  _SheetField(
                    controller: _titleCtrl,
                    hint: 'What is it? (e.g. Airport taxi)',
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _SheetField(
                    controller: _priceCtrl,
                    hint: 'Price (optional)',
                    prefixText: '₫',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _canAdd ? _add : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      disabledBackgroundColor: AppTheme.surface2,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Add to itinerary',
                        style: TextStyle(
                            color: _canAdd
                                ? Colors.white
                                : AppTheme.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
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

/// Dark-surface text field for the custom sheet.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.prefixText,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? prefixText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        prefixText: prefixText,
        prefixStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        filled: true,
        fillColor: AppTheme.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

// --- Shared bits ----------------------------------------------------------

/// Centered message for the not-loaded / invalid-dates guard states.
class _CanvasMessage extends StatelessWidget {
  const _CanvasMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Mon, Jul 14" — weekday + month + day for a day-card header.
String _dateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

/// Display label + icon for a slot key. Single source so header and sheet agree.
(String, IconData) _slotMeta(String slot) {
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

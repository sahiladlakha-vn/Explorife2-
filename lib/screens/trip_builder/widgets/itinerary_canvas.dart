import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/logic/currency.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gem.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../providers/gem_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../widgets/app_network_image.dart';
import 'add_stop_sheet.dart';

/// Center pane of the Trip Builder: a day chip strip + the active day's card,
/// whose three [TimeSlotBlock]s each open [AddStopSheet] (tap-to-search-and-
/// select, replacing the old drag-from-Discovery mechanics) via their "+ Add"
/// button. One active day is shown at a time (the shell owns [activeDay]);
/// the sidebar's route map reads the same single day.
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
    final trip = context.select<TripProvider, Trip?>((p) => p.tripById(tripId));
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
      color: AppTheme.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayChipStrip(
            activeDay: safeDay,
            dayCount: dayCount,
            onDayChanged: onDayChanged,
          ),
          const Divider(height: 1, color: AppTheme.lightBorder),
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
          // Same selector-chip convention as Step 1's vibe grid / Step 3's
          // template cards: selected = primarySoft fill + primary border
          // (1.5px), label stays lightInk always — only the icon/accent
          // switches color. Radius 16 to match those cards too (was 20, a
          // pill shape unique to this component).
          return GestureDetector(
            onTap: () => onDayChanged(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primarySoft : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.lightBorder,
                    width: selected ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Text('Day $day',
                      style: const TextStyle(
                          color: AppTheme.lightInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  if (isDeparture) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.flight_takeoff,
                        size: 14,
                        color: selected ? AppTheme.primary : AppTheme.lightMute),
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
    final symbol = currencyFor(
            context.select<TripProvider, String?>((p) => p.tripById(tripId)?.currency))
        .symbol;

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
                              color: AppTheme.lightInk,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      if (isDeparture) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: const Text('Departure',
                              style: TextStyle(
                                  color: AppTheme.lightMute,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_dateLabel(date),
                      style: const TextStyle(
                          color: AppTheme.lightMute, fontSize: 13)),
                ],
              ),
            ),
            _DayTotalPill(totalVnd: dayTotal, symbol: symbol),
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

/// Compact day-spend chip. Free gems keep this at 0 until prices are set.
class _DayTotalPill extends StatelessWidget {
  const _DayTotalPill({required this.totalVnd, required this.symbol});

  final int totalVnd;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Text('$symbol${Trip.formatVnd(totalVnd, short: true)}',
          style: const TextStyle(
              color: AppTheme.lightInk,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
    );
  }
}

// --- Time slot --------------------------------------------------------

/// One time slot of one day: its header (label + "+ Add", which opens
/// [AddStopSheet] preselected to this slot) and its placed stops.
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        // 12, matching the wizard's dominant card/field radius (was 14).
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlotHeader(
            slot: slot,
            onAdd: () => _openAddStopSheet(context),
          ),
          if (stops.isEmpty)
            const _SlotPlaceholder()
          else if (stops.length == 1)
            // No reorder machinery needed (or shown) for a single stop.
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ItineraryItemCard(
                stop: stops.first,
                gem: stops.first.isCustom
                    ? null
                    : resolveGem(stops.first.gemId!),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: stops.length,
                itemBuilder: (context, i) {
                  final s = stops[i];
                  return Padding(
                    key: ValueKey(s.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ItineraryItemCard(
                      stop: s,
                      gem: s.isCustom ? null : resolveGem(s.gemId!),
                      dragHandleIndex: i,
                    ),
                  );
                },
                onReorderItem: (oldIndex, newIndex) {
                  HapticFeedback.selectionClick();
                  // onReorderItem (unlike the deprecated onReorder)
                  // already adjusts newIndex for the removed item.
                  final reordered = List<TripStop>.from(stops);
                  reordered.insert(newIndex, reordered.removeAt(oldIndex));
                  context.read<TripProvider>().reorderStopsInSlot(
                        tripId: tripId,
                        orderedStopIds: [for (final s in reordered) s.id],
                      );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openAddStopSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddStopSheet(
              tripId: tripId, day: day, initialSlot: slot, light: true),
    );
  }
}

/// Slot label + "+ Add" affordance, which opens [AddStopSheet] preselected
/// to this slot.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.slot, required this.onAdd});

  final String slot;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = slotMeta(slot);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.lightMute),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.lightInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
            label: const Text('Add',
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

/// Empty-slot hint.
class _SlotPlaceholder extends StatelessWidget {
  const _SlotPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Text(
        'No stops yet',
        style: TextStyle(
          color: AppTheme.lightMute,
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
/// [dragHandleIndex] is only set when the card is rendered inside a
/// [ReorderableListView] (2+ stops in the slot — see [TimeSlotBlock]); it
/// draws a drag handle wired to that index. Cross-slot moves are still a
/// follow-up (see the "moveStopBetweenSlots" half of the reorder TODO this
/// replaced).
class ItineraryItemCard extends StatelessWidget {
  const ItineraryItemCard(
      {super.key, required this.stop, required this.gem, this.dragHandleIndex});

  final TripStop stop;
  final Gem? gem;
  final int? dragHandleIndex;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _titleFor();
    final symbol = currencyFor(context
            .select<TripProvider, String?>((p) => p.tripById(stop.tripId)?.currency))
        .symbol;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          if (dragHandleIndex != null)
            ReorderableDragStartListener(
              index: dragHandleIndex!,
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.drag_indicator,
                    size: 18, color: AppTheme.lightMute),
              ),
            ),
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
                        color: AppTheme.lightInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.lightMute, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PriceEditPill(
            priceVnd: stop.priceVnd,
            symbol: symbol,
            onChanged: (v) =>
                context.read<TripProvider>().updateStopPrice(stop.id, v),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<TripProvider>().removeStop(stop.id);
            },
            icon: const Icon(Icons.close,
                size: 18, color: AppTheme.lightMute),
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
      inner = const Icon(Icons.edit_note, color: AppTheme.lightMute);
    } else if (gem == null) {
      inner = const Icon(Icons.help_outline,
          color: AppTheme.lightMute, size: 20);
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
        color: AppTheme.lightCard,
        child: inner,
      ),
    );
  }
}

/// Inline price editor. Tap the pill to swap it for a compact number field;
/// commit on submit or on tapping away. Three states, per the MONEY CONTRACT
/// on [TripStop.priceVnd]: null → "Set price" (TBD), 0 → "Free" (confirmed),
/// priced → the amount.
class PriceEditPill extends StatefulWidget {
  const PriceEditPill(
      {super.key,
      required this.priceVnd,
      required this.symbol,
      required this.onChanged});

  final int? priceVnd;
  final String symbol;
  final ValueChanged<int?> onChanged;

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
    // Blank only for genuinely-unset (null) — a confirmed 0 shows '0', so
    // tapping away without typing anything can't silently flip free<->TBD.
    _ctrl.text = widget.priceVnd?.toString() ?? '';
    setState(() => _editing = true);
  }

  void _commit() {
    if (!_editing) return; // guard double-fire (onSubmitted + onTapOutside)
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Blank means TBD (null), not free (0) — an explicit '0' is what a user
    // types to confirm a stop is actually free.
    final v = digits.isEmpty ? null : int.tryParse(digits);
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
              color: AppTheme.lightInk,
              fontSize: 13,
              fontWeight: FontWeight.w700),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
          decoration: InputDecoration(
            isDense: true,
            prefixText: widget.symbol,
            prefixStyle:
                const TextStyle(color: AppTheme.lightMute, fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            filled: true,
            fillColor: AppTheme.lightCard,
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

    final tbd = widget.priceVnd == null;
    // Confirmed (free or priced) gets the primary accent — it's a real
    // answer either way; only TBD reads as "needs attention."
    final confirmed = !tbd;
    return GestureDetector(
      onTap: _start,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: confirmed ? AppTheme.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: confirmed ? AppTheme.primary : AppTheme.lightBorder),
        ),
        child: Text(
          tbd
              ? 'Set price'
              : (widget.priceVnd == 0
                  ? 'Free'
                  : '${widget.symbol}${Trip.formatVnd(widget.priceVnd!, short: true)}'),
          style: TextStyle(
              color: confirmed ? AppTheme.primary : AppTheme.lightMute,
              fontSize: 12,
              fontWeight: FontWeight.w700),
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
      color: AppTheme.lightSurface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.lightMute, fontSize: 14)),
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


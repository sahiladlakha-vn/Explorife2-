import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip.dart';
import '../../models/trip_vibe.dart';

/// Setup Step 1 — the trip's essentials: location, dates, budget, vibe.
/// Presentational: mutates the parent-owned [draft] and calls [onChanged] so the
/// sheet re-evaluates [isValid] for the Continue button. Dark colorway.
class StepOneInit extends StatefulWidget {
  const StepOneInit({
    super.key,
    required this.draft,
    required this.scrollController,
    required this.onChanged,
  });

  final TripDraft draft;
  final ScrollController scrollController;
  final VoidCallback onChanged;

  /// Location + a valid (non-zero-night) date span + positive budget + a vibe.
  /// The date span must be at least one night — a zero/negative span would
  /// divide-by-zero in the per-day helper downstream.
  static bool isValid(TripDraft d) =>
      (d.location?.trim().isNotEmpty ?? false) &&
      d.dateStart != null &&
      d.dateEnd != null &&
      d.dateEnd!.isAfter(d.dateStart!) &&
      d.budgetVnd > 0 &&
      d.vibe != null;

  @override
  State<StepOneInit> createState() => _StepOneInitState();
}

class _StepOneInitState extends State<StepOneInit> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late final TextEditingController _locationCtrl;
  late final TextEditingController _budgetCtrl;

  @override
  void initState() {
    super.initState();
    // Seed from the draft so the fields survive a Back trip from Step 2.
    _locationCtrl = TextEditingController(text: widget.draft.location ?? '');
    _budgetCtrl = TextEditingController(
        text: widget.draft.budgetVnd > 0 ? widget.draft.budgetVnd.toString() : '');
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  // Whether the chosen span is a valid (>= 1 night) range.
  bool get _datesValid {
    final s = widget.draft.dateStart, e = widget.draft.dateEnd;
    return s != null && e != null && e.isAfter(s);
  }

  String _fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  String _perDayLabel(int budget, int nights) {
    if (nights <= 0) return '';
    return 'about ₫${Trip.formatVnd((budget / nights).round(), short: true)} per day';
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDateRange:
          widget.draft.dateStart != null && widget.draft.dateEnd != null
              ? DateTimeRange(
                  start: widget.draft.dateStart!, end: widget.draft.dateEnd!)
              : null,
    );
    if (range != null) {
      widget.draft.dateStart = range.start;
      widget.draft.dateEnd = range.end;
      widget.onChanged();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final nights = _datesValid ? d.dateEnd!.difference(d.dateStart!).inDays : 0;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _label('Where to?'),
        const SizedBox(height: 8),
        TextField(
          controller: _locationCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Hoi An'),
          onChanged: (v) {
            d.location = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 24),
        _label('When?'),
        const SizedBox(height: 8),
        _DateField(
          label: _datesValid
              ? '${_fmt(d.dateStart!)} – ${_fmt(d.dateEnd!)} · $nights ${nights == 1 ? 'night' : 'nights'}'
              : 'Select your dates',
          hasValue: _datesValid,
          onTap: _pickDates,
        ),
        // Field-level error when a span was picked but is zero/negative nights.
        if (d.dateStart != null && d.dateEnd != null && !_datesValid) ...[
          const SizedBox(height: 6),
          const Text('Trip must be at least one night.',
              style: TextStyle(color: AppTheme.danger, fontSize: 12)),
        ],
        const SizedBox(height: 24),
        _label('Budget'),
        const SizedBox(height: 8),
        TextField(
          controller: _budgetCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            prefixText: '₫ ',
            hintText: '0',
            // Scale hint — the raw field accepts bare digits, so anchor the
            // magnitude a real VND budget lives at. Comma grouping matches the
            // formatted echo below (Trip.formatVnd) and the app-wide
            // convention; kept always-on so the field height doesn't jump on
            // the first keystroke.
            helperText: 'Example: 5,000,000 = ₫5M',
          ),
          onChanged: (v) {
            d.budgetVnd = int.tryParse(v) ?? 0;
            widget.onChanged();
            setState(() {}); // refresh the helper line below
          },
        ),
        if (d.budgetVnd > 0) ...[
          const SizedBox(height: 6),
          Text(
            nights > 0
                ? '₫${Trip.formatVnd(d.budgetVnd)} · ${_perDayLabel(d.budgetVnd, nights)}'
                : '₫${Trip.formatVnd(d.budgetVnd)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 24),
        _label('What\'s the vibe?'),
        const SizedBox(height: 8),
        _vibeGrid(),
        // TODO(travelers): a travelers stepper goes here once trip_collaborators
        // reads ship and the draft/migration gain a travelers field.
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700));

  Widget _vibeGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 480 ? 2 : 4;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: TripVibe.values.map((v) {
            final selected = widget.draft.vibe == v;
            return GestureDetector(
              onTap: () {
                // One-of-four required field: switch selection, never clear.
                if (!selected) {
                  widget.draft.vibe = v;
                  widget.onChanged();
                  setState(() {});
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.primarySoft : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.divider,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(v.icon,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        size: 24),
                    const Spacer(),
                    Text(v.label,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(v.tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            height: 1.25)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Tappable field that mimics an input row but opens the date range picker.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: hasValue
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

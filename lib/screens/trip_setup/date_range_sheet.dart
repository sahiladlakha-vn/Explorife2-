import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Custom trip-dates picker — replaces the stock [showDateRangePicker] with a
/// "Quick Selection" presets row (Weekend Getaway / 1 Week Trip / 2 Weeks Trip)
/// above a browsable multi-month calendar. Light colorway, matching the rest
/// of the trip-setup flow.
Future<DateTimeRange?> showTripDateRangeSheet(
  BuildContext context, {
  DateTimeRange? initialRange,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DateRangeSheet(initialRange: initialRange),
  );
}

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({this.initialRange});

  final DateTimeRange? initialRange;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  late final DateTime _today;
  late DateTime _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _hasSelection = widget.initialRange != null;
    _start = widget.initialRange?.start ?? _today;
    _end = widget.initialRange?.end;
  }

  late bool _hasSelection;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime day) {
    setState(() {
      if (!_hasSelection || _end != null) {
        _hasSelection = true;
        _start = day;
        _end = null;
      } else if (day.isBefore(_start)) {
        _start = day;
        _end = null;
      } else if (_isSameDay(day, _start)) {
        // single-day tap on the existing start: no-op, needs a second day.
      } else {
        _end = day;
      }
    });
  }

  void _applyPreset(DateTime start, DateTime end) {
    setState(() {
      _hasSelection = true;
      _start = start;
      _end = end;
    });
  }

  void _presetWeekend() {
    var friday = _today;
    while (friday.weekday != DateTime.friday) {
      friday = friday.add(const Duration(days: 1));
    }
    _applyPreset(friday, friday.add(const Duration(days: 2)));
  }

  void _presetOneWeek() {
    final start = _today.add(const Duration(days: 1));
    _applyPreset(start, start.add(const Duration(days: 7)));
  }

  void _presetTwoWeeks() {
    final start = _today.add(const Duration(days: 1));
    _applyPreset(start, start.add(const Duration(days: 14)));
  }

  String _fmt(DateTime d) => '${_months[d.month - 1].substring(0, 3)} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final canApply = _hasSelection && _end != null && _end!.isAfter(_start);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.lightSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.lightMute,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trip dates',
                      style: TextStyle(
                        color: AppTheme.lightInk,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.lightCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: const Icon(Icons.close,
                          color: AppTheme.lightMute, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _hasSelection
                      ? (_end != null
                          ? '${_fmt(_start)} – ${_fmt(_end!)} · ${_end!.difference(_start).inDays} ${_end!.difference(_start).inDays == 1 ? 'night' : 'nights'}'
                          : '${_fmt(_start)} · pick an end date')
                      : 'Select your dates',
                  style: const TextStyle(
                      color: AppTheme.lightMute,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick Selection',
                  style: TextStyle(
                      color: AppTheme.lightInk.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _PresetPill(label: 'Weekend Getaway', onTap: _presetWeekend),
                  const SizedBox(width: 8),
                  _PresetPill(label: '1 Week Trip', onTap: _presetOneWeek),
                  const SizedBox(width: 8),
                  _PresetPill(label: '2 Weeks Trip', onTap: _presetTwoWeeks),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Divider(height: 25, color: AppTheme.lightBorder),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: List.generate(6, (i) {
                  final month = DateTime(_today.year, _today.month + i, 1);
                  return _MonthGrid(
                    month: month,
                    monthLabel: _months[month.month - 1],
                    weekdayLabels: _weekdayLabels,
                    today: _today,
                    start: _hasSelection ? _start : null,
                    end: _end,
                    onDayTap: _onDayTap,
                  );
                }),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.lightBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canApply
                      ? () => Navigator.of(context)
                          .pop(DateTimeRange(start: _start, end: _end!))
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.lightBorder,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.luggage_outlined, size: 15, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.lightInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.monthLabel,
    required this.weekdayLabels,
    required this.today,
    required this.start,
    required this.end,
    required this.onDayTap,
  });

  final DateTime month;
  final String monthLabel;
  final List<String> weekdayLabels;
  final DateTime today;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onDayTap;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday % 7;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$monthLabel ${month.year}',
              style: const TextStyle(
                  color: AppTheme.lightInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: weekdayLabels
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: const TextStyle(
                                color: AppTheme.lightMute,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _dayCell(DateTime(month.year, month.month, d)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final isStart = start != null && _isSameDay(day, start!);
    final isEnd = end != null && _isSameDay(day, end!);
    final inRange = start != null &&
        end != null &&
        day.isAfter(start!) &&
        day.isBefore(end!);
    final isPast = day.isBefore(today);
    final isRangeEndpoint = isStart || isEnd;

    return GestureDetector(
      onTap: isPast ? null : () => onDayTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: inRange ? AppTheme.teal.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.horizontal(
            left: (isStart && !isEnd) ? const Radius.circular(18) : Radius.zero,
            right: (isEnd && !isStart) ? const Radius.circular(18) : Radius.zero,
          ),
        ),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRangeEndpoint ? AppTheme.primary : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isPast
                    ? AppTheme.lightMute.withValues(alpha: 0.4)
                    : isRangeEndpoint
                        ? Colors.white
                        : AppTheme.lightInk,
                fontSize: 13.5,
                fontWeight: isRangeEndpoint ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

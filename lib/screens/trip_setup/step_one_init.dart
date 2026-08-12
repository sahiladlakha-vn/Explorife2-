import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip.dart';
import '../../models/trip_vibe.dart';
import 'date_range_sheet.dart';

/// Setup Step 1 — the trip's essentials: location, dates, budget, vibe.
/// Presentational: mutates the parent-owned [draft] and calls [onChanged] so the
/// sheet re-evaluates [isValid] for the Continue button. Light colorway,
/// matching Profile — also reused as-is by EditTripSheet.
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
  final _locationFocus = FocusNode();
  final _geo = GeocodingService();
  Timer? _geoDebounce;
  List<GeoPlace> _suggestions = [];
  bool _searching = false;
  // True once a debounced search has resolved for the CURRENT text — gates
  // "No matches found" so it can't flash before the first search runs.
  bool _searchedCurrentText = false;

  @override
  void initState() {
    super.initState();
    // Seed from the draft so the fields survive a Back trip from Step 2.
    _locationCtrl = TextEditingController(text: widget.draft.location ?? '');
    _budgetCtrl = TextEditingController(
        text: widget.draft.budgetVnd > 0 ? widget.draft.budgetVnd.toString() : '');
    // Clear stale suggestions once focus moves elsewhere WITHOUT a selection
    // (e.g. the user tabs down to the date field instead of picking a row).
    // Delayed rather than immediate: tapping a suggestion itself blurs this
    // field first (see the class doc on _locationSuggestions for why hiding
    // the list synchronously on blur is the actual bug this works around) —
    // the delay gives that tap's own onTap a chance to land before this
    // would otherwise rip the list out from under it.
    _locationFocus.addListener(() {
      if (_locationFocus.hasFocus) return;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_locationFocus.hasFocus) {
          setState(() => _suggestions = []);
        }
      });
    });
  }

  @override
  void dispose() {
    _geoDebounce?.cancel();
    _locationCtrl.dispose();
    _budgetCtrl.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  // Free-typed text always stays valid input (StepOneInit.isValid only checks
  // non-empty) — lat/lng just goes back to unknown, same as any trip created
  // before this field existed. Coordinates are only ever set by _selectPlace.
  void _onLocationChanged(String v) {
    widget.draft.location = v;
    widget.draft.locationLat = null;
    widget.draft.locationLng = null;
    widget.onChanged();

    _geoDebounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _suggestions = [];
        _searching = false;
        _searchedCurrentText = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchedCurrentText = false;
    });
    _geoDebounce = Timer(const Duration(milliseconds: 320), () => _search(q));
  }

  Future<void> _search(String query) async {
    final results = await _geo.search(query);
    // Drop a stale response — the field has moved on to different text since
    // this request went out.
    if (!mounted || _locationCtrl.text.trim() != query) return;
    setState(() {
      _suggestions = results;
      _searching = false;
      _searchedCurrentText = true;
    });
  }

  void _selectPlace(GeoPlace place) {
    final label = place.fullName.isNotEmpty ? place.fullName : place.name;
    _locationCtrl.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    widget.draft.location = label;
    widget.draft.locationLat = place.lat;
    widget.draft.locationLng = place.lng;
    widget.onChanged();
    setState(() {
      _suggestions = [];
      _searching = false;
      _searchedCurrentText = false;
    });
    _locationFocus.unfocus();
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
    final range = await showTripDateRangeSheet(
      context,
      initialRange:
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
          focusNode: _locationFocus,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppTheme.lightInk, fontSize: 15),
          decoration: _lightDecoration(hintText: 'e.g. Hoi An').copyWith(
            prefixIcon: const Icon(Icons.location_on_outlined,
                size: 18, color: AppTheme.lightMute),
          ),
          onChanged: _onLocationChanged,
        ),
        _locationSuggestions(),
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
          style: const TextStyle(color: AppTheme.lightInk, fontSize: 15),
          decoration: _lightDecoration(
            hintText: '0',
            prefixText: '₫ ',
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
            style: const TextStyle(color: AppTheme.lightMute, fontSize: 12),
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
          color: AppTheme.lightInk, fontSize: 15, fontWeight: FontWeight.w700));

  /// Inline (not floating) so it can't overlap Step 1's later fields inside
  /// the surrounding ListView — same choice AddStopSheet/TravelerLookupSheet
  /// make for their own result lists. Renders nothing when there's no
  /// in-flight search, no results, and no completed empty search to report.
  Widget _locationSuggestions() {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _suggestionBox(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary),
              ),
            ),
          ),
        ),
      );
    }
    if (_suggestions.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _suggestionBox(
          child: Column(
            children: [
              for (final (i, place) in _suggestions.indexed)
                _PlaceRow(
                  place: place,
                  divider: i > 0,
                  onTap: () => _selectPlace(place),
                ),
            ],
          ),
        ),
      );
    }
    if (_searchedCurrentText) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _suggestionBox(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Text('No matches found.',
                style: TextStyle(color: AppTheme.lightMute, fontSize: 13)),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _suggestionBox({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      );

  InputDecoration _lightDecoration({
    required String hintText,
    String? prefixText,
    String? helperText,
  }) =>
      InputDecoration(
        hintText: hintText,
        prefixText: prefixText,
        helperText: helperText,
        hintStyle: const TextStyle(color: AppTheme.lightMute),
        prefixStyle: const TextStyle(color: AppTheme.lightMute),
        helperStyle: const TextStyle(color: AppTheme.lightMute),
        filled: true,
        fillColor: AppTheme.lightCard,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      );

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
                  color: selected ? AppTheme.primarySoft : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.lightBorder,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(v.icon,
                        color: selected ? AppTheme.primary : AppTheme.lightMute,
                        size: 24),
                    const Spacer(),
                    Text(v.label,
                        style: const TextStyle(
                            color: AppTheme.lightInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(v.tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 11, height: 1.25)),
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

/// One autocomplete result: place icon, short name, full formatted name.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow(
      {required this.place, required this.divider, required this.onTap});

  final GeoPlace place;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: AppTheme.lightBorder))
              : null,
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined,
                size: 18, color: AppTheme.lightMute),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name.isNotEmpty ? place.name : place.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.lightInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  if (place.fullName.isNotEmpty && place.fullName != place.name) ...[
                    const SizedBox(height: 2),
                    Text(place.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
          color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: AppTheme.lightMute),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: hasValue ? AppTheme.lightInk : AppTheme.lightMute, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

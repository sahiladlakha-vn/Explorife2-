import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/logic/currency.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_traveler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/splits_provider.dart';
import '../../providers/trip_provider.dart';

/// Category vocabulary — identical keys/labels to the trip Dashboard's own
/// _dashboardCategoryLabels (trips_tab.dart), duplicated here rather than
/// exported since that map is private to a part-file; keep the two in sync
/// by hand if either changes.
const Map<String, String> expenseCategoryLabels = {
  'stay': 'Stay',
  'food': 'Food',
  'transit': 'Transport',
  'activity': 'Activities',
  'misc': 'Misc',
};

class _Palette {
  final Color surface;
  final Color card;
  final Color border;
  final Color ink;
  final Color mute;
  const _Palette(
      {required this.surface,
      required this.card,
      required this.border,
      required this.ink,
      required this.mute});

  static const dark = _Palette(
    surface: AppTheme.surface,
    card: AppTheme.surface2,
    border: AppTheme.divider,
    ink: AppTheme.textPrimary,
    mute: AppTheme.textSecondary,
  );
  static const light = _Palette(
    surface: AppTheme.lightSurface,
    card: AppTheme.lightCard,
    border: AppTheme.lightBorder,
    ink: AppTheme.lightInk,
    mute: AppTheme.lightMute,
  );
}

/// Single add-expense implementation, shared by the standalone Splits
/// feature (SplitDetailScreen, dark, no trip/travelers context) and the
/// trip-scoped "+ Add Expense" entry points (Overview tab's trip card,
/// light, with a resolved groupId + this trip's traveler list for the
/// paid-by picker). Captures description, amount, category, date, and — when
/// [travelers] is non-empty — who paid; otherwise defaults silently to the
/// current user, matching the sheet's original description-and-amount-only
/// behavior before this was extended.
class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({
    super.key,
    required this.groupId,
    this.tripId,
    this.travelers = const [],
    this.light = false,
    this.initialTitle,
    this.initialAmount,
    this.initialCategory,
  });

  final String groupId;

  /// Stamps the new expense's trip_id and keys SplitsProvider's per-trip
  /// cache so the Dashboard/Overview reflect it immediately. Null for the
  /// standalone Splits feature, where an expense has no trip association.
  final String? tripId;

  /// This trip's travelers, for the paid-by picker. Empty hides the picker
  /// entirely and defaults to the current user (the standalone Splits
  /// screen's case — it has no "trip travelers" concept).
  final List<TripTraveler> travelers;

  final bool light;

  /// Prefill for the "Log as shared expense" action on a Booking card
  /// (trips_tab.dart) — seeds the form but still requires the user to review
  /// and hit Save; nothing is created automatically. All three are optional
  /// and independent of each other.
  final String? initialTitle;
  final double? initialAmount;
  final String? initialCategory;

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  late final _descCtrl = TextEditingController(text: widget.initialTitle ?? '');
  late final _amountCtrl = TextEditingController(
      text: widget.initialAmount == null
          ? ''
          : widget.initialAmount == widget.initialAmount!.roundToDouble()
              ? widget.initialAmount!.round().toString()
              : widget.initialAmount.toString());
  late String _category = widget.initialCategory ?? 'misc';
  DateTime _date = DateTime.now();
  String? _paidBy;
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String _resolvedPaidBy(BuildContext context) =>
      _paidBy ?? context.read<AuthProvider>().user?.id ?? '';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 2),
      lastDate: DateTime(_date.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final title = _descCtrl.text.trim();
    if (title.isEmpty || amount == null || amount <= 0) return;

    setState(() => _saving = true);
    // Trip-scoped expenses inherit that trip's own currency (per-trip
    // currency, no conversion — lib/core/logic/currency.dart); the standalone
    // Splits screen has no trip to inherit from, so it keeps the column's
    // 'USD' default.
    final tripCurrency = widget.tripId != null
        ? context.read<TripProvider>().tripById(widget.tripId!)?.currency
        : null;
    final ok = await context.read<SplitsProvider>().addExpense(
          groupId: widget.groupId,
          tripId: widget.tripId,
          paidBy: _resolvedPaidBy(context),
          title: title,
          amount: amount,
          currency:
              widget.tripId != null ? (tripCurrency ?? 'VND') : 'USD',
          category: _category,
          expenseDate: _date,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add expense')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.light ? _Palette.light : _Palette.dark;
    final me = context.watch<AuthProvider>().user?.id;
    final effectivePaidBy = _paidBy ?? me;
    final amountHint = widget.tripId != null
        ? 'Amount (${currencyFor(context
            .watch<TripProvider>()
            .tripById(widget.tripId!)
            ?.currency)
            .symbol})'
        : 'Amount (\$)';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration:
                    BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Text('Add expense',
                style: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              autofocus: true,
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: _decoration(p, 'Description (e.g. Hotel, Dinner)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: _decoration(p, amountHint),
            ),
            const SizedBox(height: 14),
            Text('Category',
                style: TextStyle(color: p.mute, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in expenseCategoryLabels.entries)
                  _Chip(
                    label: entry.value,
                    selected: _category == entry.key,
                    palette: p,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: Row(children: [
                  Icon(Icons.event_outlined, size: 18, color: p.mute),
                  const SizedBox(width: 10),
                  Text(_fmtDate(_date), style: TextStyle(color: p.ink, fontSize: 14)),
                ]),
              ),
            ),
            if (widget.travelers.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Paid by',
                  style: TextStyle(color: p.mute, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in widget.travelers)
                    _Chip(
                      label: t.userId == me ? '${t.displayName} (You)' : t.displayName,
                      selected: effectivePaidBy == t.userId,
                      palette: p,
                      onTap: () => setState(() => _paidBy = t.userId),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add expense',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(_Palette p, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: p.mute, fontSize: 14),
        filled: true,
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.palette, required this.onTap});
  final String label;
  final bool selected;
  final _Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppTheme.primary : palette.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : palette.mute)),
      ),
    );
  }
}

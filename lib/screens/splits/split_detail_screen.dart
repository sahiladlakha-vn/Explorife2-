import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/hike.dart';
import '../../providers/splits_provider.dart';
import '../../widgets/common/add_expense_sheet.dart';

class SplitDetailScreen extends StatefulWidget {
  final String groupId;
  const SplitDetailScreen({super.key, required this.groupId});
  @override
  State<SplitDetailScreen> createState() => _SplitDetailScreenState();
}

class _SplitDetailScreenState extends State<SplitDetailScreen> {
  SplitGroup? _group;
  List<SplitExpense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prov = context.read<SplitsProvider>();
    final cached = prov.groups.where((g) => g.id == widget.groupId).firstOrNull;
    final expenses = await prov.fetchExpenses(widget.groupId);
    if (mounted) setState(() {
      _group = cached;
      _expenses = expenses;
      _loading = false;
    });
  }

  double get _total => _expenses.fold(0.0, (s, e) => s + e.amount);

  // Shared with the trip-scoped "+ Add Expense" entry points (Overview tab)
  // — see AddExpenseSheet's own doc comment. This call site passes no
  // tripId/travelers: a standalone split group has no trip association and
  // no "trip travelers" concept, so the sheet falls back to its original
  // description-and-amount-only, paid-by-self behavior.
  void _showAddExpense() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(groupId: widget.groupId, light: true),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/splits')),
        title: Text(_group?.name ?? 'Trip',
            style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
        actions: [
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddExpense),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(children: [
              // Total banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TOTAL SPENT',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.lightMute)),
                      Text('\$${_total.toStringAsFixed(2)}',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 36, color: AppTheme.primary)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('EXPENSES',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.lightMute)),
                      Text('${_expenses.length}',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 36, color: AppTheme.lightInk)),
                    ]),
                  ],
                ),
              ),

              // Expense list
              Expanded(
                child: _expenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💸', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 16),
                            Text('No expenses yet',
                                style: GoogleFonts.bebasNeue(
                                    fontSize: 22,
                                    color: AppTheme.lightMute)),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _showAddExpense,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary),
                              child: Text('Add First Expense',
                                  style: GoogleFonts.fredoka(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _expenses.length,
                        itemBuilder: (ctx, i) => _ExpenseRow(expense: _expenses[i]),
                      ),
              ),
            ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpense,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final SplitExpense expense;
  const _ExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(expense.title,
                style: GoogleFonts.fredoka(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.lightInk)),
            Text(
              '${expense.createdAt.day}/${expense.createdAt.month}/${expense.createdAt.year}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.lightMute),
            ),
          ]),
        ),
        Text(
          '\$${expense.amount.toStringAsFixed(2)}',
          style: GoogleFonts.bebasNeue(
              fontSize: 20, color: AppTheme.primary, letterSpacing: 0.5),
        ),
      ]),
    );
  }
}

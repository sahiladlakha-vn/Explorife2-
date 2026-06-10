import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/hike.dart';
import '../../providers/auth_provider.dart';
import '../../providers/hike_provider.dart';

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
    final prov = context.read<HikeProvider>();
    final cached = prov.groups.where((g) => g.id == widget.groupId).firstOrNull;
    final expenses = await prov.fetchExpenses(widget.groupId);
    if (mounted) setState(() {
      _group = cached;
      _expenses = expenses;
      _loading = false;
    });
  }

  double get _total => _expenses.fold(0.0, (s, e) => s + e.amount);

  void _showAddExpense() {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('ADD EXPENSE',
              style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          TextField(
            controller: descCtrl,
            autofocus: true,
            style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
            decoration: _inputDeco('Description (e.g. Fuel, Hostel)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
            decoration: _inputDeco('Amount (USD)'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text);
                if (descCtrl.text.trim().isEmpty || amt == null) return;
                final auth = context.read<AuthProvider>();
                Navigator.pop(ctx);
                final ok = await context.read<HikeProvider>().addExpense(
                  groupId: widget.groupId,
                  paidBy: auth.user?.id ?? '',
                  description: descCtrl.text.trim(),
                  amount: amt,
                );
                if (ok) _load();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text('ADD',
                  style: GoogleFonts.bebasNeue(fontSize: 18, letterSpacing: 0.5)),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(
            color: AppTheme.textSecondary.withOpacity(0.5), fontSize: 14),
        filled: true,
        fillColor: AppTheme.surface2,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
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
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TOTAL SPENT',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.textSecondary)),
                      Text('\$${_total.toStringAsFixed(2)}',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 36, color: AppTheme.primary)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('EXPENSES',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppTheme.textSecondary)),
                      Text('${_expenses.length}',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 36, color: AppTheme.textPrimary)),
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
                                    color: AppTheme.textSecondary)),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _showAddExpense,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary),
                              child: Text('Add First Expense',
                                  style: GoogleFonts.dmSans(
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(expense.description,
                style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            Text(
              '${expense.createdAt.day}/${expense.createdAt.month}/${expense.createdAt.year}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppTheme.textSecondary),
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

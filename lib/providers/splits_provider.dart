import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hike.dart';

/// Owns the expense-splitting domain: trip groups, their membership, and the
/// expenses logged against them. Previously these lived on `HikeProvider`
/// alongside the unrelated hike-tracking state; they were split out so each
/// provider has a single responsibility and screens only listen to the slice
/// of state they actually use.
class SplitsProvider extends ChangeNotifier {
  static final _db = Supabase.instance.client;

  List<SplitGroup> _groups = [];

  List<SplitGroup> get groups => _groups;

  Future<void> fetchGroups(String userId) async {
    try {
      // Get groups where user is a member
      final memberData = await _db
          .from('split_group_members')
          .select('group_id')
          .eq('user_id', userId);
      final ids = (memberData as List).map((e) => e['group_id'] as String).toList();
      if (ids.isEmpty) {
        _groups = [];
        notifyListeners();
        return;
      }
      final groupData = await _db
          .from('split_groups')
          .select()
          .inFilter('id', ids)
          .order('created_at', ascending: false);
      _groups = (groupData as List).map((e) => SplitGroup.fromJson(e)).toList();
    } catch (e) {
      debugPrint('fetchGroups error: $e');
    }
    notifyListeners();
  }

  Future<List<SplitExpense>> fetchExpenses(String groupId) async {
    try {
      final data = await _db
          .from('split_expenses')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => SplitExpense.fromJson(e)).toList();
    } catch (e) {
      debugPrint('fetchExpenses error: $e');
      return [];
    }
  }

  /// Total spend across every split group the user belongs to, plus the group
  /// count, in a fixed **two** queries — the member group ids, then a single
  /// expense fetch filtered to those ids. Replaces the previous 1 + N pattern
  /// (one expense round-trip per group) that scaled linearly with membership.
  Future<({double spent, int groups})> fetchSpendSummary(String userId) async {
    try {
      final memberData = await _db
          .from('split_group_members')
          .select('group_id')
          .eq('user_id', userId);
      final ids =
          (memberData as List).map((e) => e['group_id'] as String).toList();
      if (ids.isEmpty) return (spent: 0.0, groups: 0);

      final rows = await _db
          .from('split_expenses')
          .select('amount')
          .inFilter('group_id', ids);
      final spent = (rows as List).fold<double>(
        0,
        (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0),
      );
      return (spent: spent, groups: ids.length);
    } catch (e) {
      debugPrint('fetchSpendSummary error: $e');
      return (spent: 0.0, groups: 0);
    }
  }

  Future<SplitGroup?> createGroup({
    required String userId,
    required String name,
    String? description,
  }) async {
    try {
      final data = await _db.from('split_groups').insert({
        'name': name,
        'description': description,
        'created_by': userId,
      }).select().single();
      // Add creator as member
      await _db.from('split_group_members').insert({
        'group_id': data['id'],
        'user_id': userId,
      });
      await fetchGroups(userId);
      return SplitGroup.fromJson(data);
    } catch (e) {
      debugPrint('createGroup error: $e');
      return null;
    }
  }

  Future<bool> addExpense({
    required String groupId,
    required String paidBy,
    required String title,
    required double amount,
    String currency = 'USD',
    String? tripId,
    String? category,
  }) async {
    try {
      // 'title' — NOT 'description'. The live split_expenses table has no
      // description column; this insert previously sent a key PostgREST
      // rejected on every call, so every "Add expense" tap silently failed
      // (addExpense caught the error and returned false with no user-facing
      // message). Confirmed against information_schema.columns.
      await _db.from('split_expenses').insert({
        'group_id': groupId,
        'paid_by': paidBy,
        'title': title,
        'amount': amount,
        'currency': currency,
        if (tripId != null) 'trip_id': tripId,
        if (category != null) 'category': category,
      });
      return true;
    } catch (e) {
      debugPrint('addExpense error: $e');
      return false;
    }
  }

  // ── Trip Dashboard ──────────────────────────────────────────────────────
  // Caches keyed by tripId (mirrors BookingProvider/TripSetupProvider). Key
  // present with an empty list == "fetched, none"; a MISSING key == "never
  // fetched".
  final Map<String, List<SplitExpense>> _expensesByTrip = {};
  final Map<String, List<SplitExpenseShare>> _sharesByTrip = {};
  final Map<String, List<SplitSettlement>> _settlementsByTrip = {};
  final Map<String, bool> _dashboardLoadingByTrip = {};
  final Map<String, String?> _dashboardErrorByTrip = {};

  List<SplitExpense> expensesForTrip(String tripId) =>
      _expensesByTrip[tripId] ?? const <SplitExpense>[];
  List<SplitExpenseShare> sharesForTrip(String tripId) =>
      _sharesByTrip[tripId] ?? const <SplitExpenseShare>[];
  List<SplitSettlement> settlementsForTrip(String tripId) =>
      _settlementsByTrip[tripId] ?? const <SplitSettlement>[];
  bool isDashboardLoading(String tripId) =>
      _dashboardLoadingByTrip[tripId] ?? false;
  String? dashboardErrorFor(String tripId) => _dashboardErrorByTrip[tripId];
  bool hasLoadedDashboard(String tripId) => _expensesByTrip.containsKey(tripId);

  /// Loads everything the trip Dashboard needs: this trip's expenses, the
  /// per-member shares recorded against them (usually empty — see
  /// [SplitExpenseShare]'s doc comment), and settlements for whichever
  /// group(s) those expenses belong to. Settlements have no trip_id of their
  /// own (only group_id), so "this trip's settlements" means "settlements on
  /// any group this trip's expenses reference" — an indirect but correct
  /// lookup given the live schema.
  Future<void> loadTripDashboard(String tripId, {bool force = false}) async {
    if (!force &&
        (hasLoadedDashboard(tripId) || (_dashboardLoadingByTrip[tripId] ?? false))) {
      return;
    }
    _dashboardLoadingByTrip[tripId] = true;
    _dashboardErrorByTrip[tripId] = null;
    notifyListeners();

    try {
      final expenseRows = await _db
          .from('split_expenses')
          .select()
          .eq('trip_id', tripId)
          .order('expense_date', ascending: false);
      final expenses =
          (expenseRows as List).map((e) => SplitExpense.fromJson(e)).toList();
      _expensesByTrip[tripId] = expenses;

      final expenseIds = expenses.map((e) => e.id).toList();
      _sharesByTrip[tripId] = expenseIds.isEmpty
          ? []
          : (await _db
                  .from('split_expense_shares')
                  .select()
                  .inFilter('expense_id', expenseIds) as List)
              .map((e) => SplitExpenseShare.fromJson(e))
              .toList();

      final groupIds =
          expenses.map((e) => e.groupId).whereType<String>().toSet().toList();
      _settlementsByTrip[tripId] = groupIds.isEmpty
          ? []
          : (await _db
                  .from('split_settlements')
                  .select()
                  .inFilter('group_id', groupIds) as List)
              .map((e) => SplitSettlement.fromJson(e))
              .toList();
    } catch (e) {
      _dashboardErrorByTrip[tripId] = e.toString();
    } finally {
      _dashboardLoadingByTrip[tripId] = false;
      notifyListeners();
    }
  }

  void clear() {
    _groups = [];
    _expensesByTrip.clear();
    _sharesByTrip.clear();
    _settlementsByTrip.clear();
    _dashboardLoadingByTrip.clear();
    _dashboardErrorByTrip.clear();
    notifyListeners();
  }
}

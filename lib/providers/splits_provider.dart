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
    required String description,
    required double amount,
    String currency = 'USD',
  }) async {
    try {
      await _db.from('split_expenses').insert({
        'group_id': groupId,
        'paid_by': paidBy,
        'description': description,
        'amount': amount,
        'currency': currency,
      });
      return true;
    } catch (e) {
      debugPrint('addExpense error: $e');
      return false;
    }
  }
}

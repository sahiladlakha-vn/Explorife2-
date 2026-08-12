// Pure derived logic for the trip Dashboard's Expenses/Settle-up cards.
// Deliberately UI-free and provider-free — every function takes plain values
// (lists of models, a member-id list) and returns plain values, so this file
// is deterministic and unit-testable without a database or a widget tree.
//
// MONEY NOTE: split_expenses/split_expense_shares/split_settlements store
// `amount` as a raw numeric (double here), not the *_vnd bigint convention
// used elsewhere in this app (trips.budget_vnd, trip_stops.price_vnd, …).
// This file works in that raw double space; the UI layer rounds to int VND
// only at render time via Trip.formatVnd, same as it already does for any
// other double-producing computation.

import '../../models/hike.dart';

/// A net amount [fromUserId] owes [toUserId], after settling every other
/// pairwise debt against it (see [settleUpBalances]'s doc for the algorithm).
class Balance {
  final String fromUserId;
  final String toUserId;
  final double amountVnd;

  const Balance({
    required this.fromUserId,
    required this.toUserId,
    required this.amountVnd,
  });
}

/// Below this, a balance is treated as fully settled — guards against
/// floating-point dust (e.g. an equal split of ₫100,000 across 3 people
/// leaving a fractional-đồng remainder) showing up as a spurious tiny debt.
const double _zeroThreshold = 1.0;

/// Computes who owes whom, and how much, across [expenses] (already filtered
/// to one trip and to `!isSettlement` — this function doesn't re-filter,
/// so a caller that wants settlement-type rows excluded must do that first).
///
/// PER-EXPENSE RESOLUTION:
///   - If [shares] has any rows for that expense (`expenseId` matches), those
///     real per-member amounts are used as-is — this is what a genuine
///     'exact'/'percentage' split looks like once something actually writes
///     [SplitExpenseShare] rows (nothing does today; see that model's doc).
///   - Otherwise, the expense's [SplitExpense.amount] is split EQUALLY across
///     every id in [memberUserIds] — the only split math avaliable without
///     stored per-member shares, which also happens to match `split_type`'s
///     'equal' default.
/// An expense with no [SplitExpense.paidBy] is skipped entirely (nothing to
/// attribute a payment to).
///
/// [settlements] (real recorded payments, e.g. "Minh paid Sahil ₫420k") are
/// netted in afterward, so a debt someone already paid back doesn't keep
/// showing as outstanding.
///
/// RESULT: a minimal set of pairwise transactions that clears every net
/// balance (a classic greedy debt-simplification pass — largest debtor pays
/// largest creditor, repeat), not literally "every expense's split" replayed
/// — that would produce far more transactions than necessary between the
/// same group of people.
List<Balance> settleUpBalances({
  required List<SplitExpense> expenses,
  required List<SplitExpenseShare> shares,
  required List<SplitSettlement> settlements,
  required List<String> memberUserIds,
}) {
  // net[uid] > 0  => owed money (fronted more than their share)
  // net[uid] < 0  => owes money
  final net = <String, double>{for (final id in memberUserIds) id: 0.0};

  final sharesByExpense = <String, List<SplitExpenseShare>>{};
  for (final s in shares) {
    if (s.expenseId == null) continue;
    (sharesByExpense[s.expenseId!] ??= []).add(s);
  }

  for (final e in expenses) {
    final payer = e.paidBy;
    if (payer == null) continue;

    final recorded = sharesByExpense[e.id];
    if (recorded != null && recorded.isNotEmpty) {
      for (final s in recorded) {
        if (s.userId == null) continue;
        net[s.userId!] = (net[s.userId!] ?? 0) - s.amount;
      }
    } else if (memberUserIds.isNotEmpty) {
      final share = e.amount / memberUserIds.length;
      for (final uid in memberUserIds) {
        net[uid] = (net[uid] ?? 0) - share;
      }
    }
    net[payer] = (net[payer] ?? 0) + e.amount;
  }

  // Net out payments already recorded between these same people: the payer
  // (fromUser) reduces their debt (net moves toward 0 / positive), the
  // recipient (toUser) reduces what they're owed.
  for (final s in settlements) {
    if (s.fromUser == null || s.toUser == null) continue;
    net[s.fromUser!] = (net[s.fromUser!] ?? 0) + s.amount;
    net[s.toUser!] = (net[s.toUser!] ?? 0) - s.amount;
  }

  final debtors = <MapEntry<String, double>>[];
  final creditors = <MapEntry<String, double>>[];
  net.forEach((uid, n) {
    if (n < -_zeroThreshold) {
      debtors.add(MapEntry(uid, -n));
    } else if (n > _zeroThreshold) {
      creditors.add(MapEntry(uid, n));
    }
  });
  debtors.sort((a, b) => b.value.compareTo(a.value));
  creditors.sort((a, b) => b.value.compareTo(a.value));

  final result = <Balance>[];
  var di = 0, ci = 0;
  while (di < debtors.length && ci < creditors.length) {
    final debtorId = debtors[di].key;
    final creditorId = creditors[ci].key;
    final debtLeft = debtors[di].value;
    final creditLeft = creditors[ci].value;
    final amt = debtLeft < creditLeft ? debtLeft : creditLeft;

    if (amt > _zeroThreshold) {
      result.add(
          Balance(fromUserId: debtorId, toUserId: creditorId, amountVnd: amt));
    }

    debtors[di] = MapEntry(debtorId, debtLeft - amt);
    creditors[ci] = MapEntry(creditorId, creditLeft - amt);
    if (debtors[di].value <= _zeroThreshold) di++;
    if (creditors[ci].value <= _zeroThreshold) ci++;
  }

  return result;
}

/// Sums [expenses] by category, bucketing anything outside the 5 tracked
/// buckets (stay/food/transit/activity/misc) into 'misc' — the 8-value
/// category vocabulary that split_expenses/trip_category_budgets both allow
/// reserves shopping/insurance/flights for later; nothing seeds planned
/// amounts for them yet (see trip_budget_template.dart), so they read as
/// miscellaneous spend rather than their own unplanned rows. Excludes
/// [SplitExpense.isSettlement] rows — a balancing payment isn't spend.
Map<String, double> actualByCategory(List<SplitExpense> expenses) {
  const tracked = {'stay', 'food', 'transit', 'activity'};
  final totals = <String, double>{
    'stay': 0,
    'food': 0,
    'transit': 0,
    'activity': 0,
    'misc': 0,
  };
  for (final e in expenses) {
    if (e.isSettlement) continue;
    final bucket = tracked.contains(e.category) ? e.category! : 'misc';
    totals[bucket] = (totals[bucket] ?? 0) + e.amount;
  }
  return totals;
}

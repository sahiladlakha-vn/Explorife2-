class HikeTrack {
  final String id;
  final String userId;
  final String title;
  final String activityType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? distanceKm;
  final int? durationSeconds;
  final double? elevationGainM;
  final bool featured;
  final DateTime createdAt;

  const HikeTrack({
    required this.id,
    required this.userId,
    required this.title,
    required this.activityType,
    required this.startedAt,
    this.endedAt,
    this.distanceKm,
    this.durationSeconds,
    this.elevationGainM,
    required this.featured,
    required this.createdAt,
  });

  factory HikeTrack.fromJson(Map<String, dynamic> json) => HikeTrack(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String? ?? 'Untitled Hike',
        activityType: json['activity_type'] as String? ?? 'hiking',
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ?? DateTime.now(),
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        durationSeconds: json['duration_seconds'] as int?,
        elevationGainM: (json['elevation_gain_m'] as num?)?.toDouble(),
        featured: json['featured'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get durationFormatted {
    if (durationSeconds == null) return '—';
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static const Map<String, String> activityEmoji = {
    'hiking': '🥾',
    'trail_running': '🏃',
    'cycling': '🚴',
    'climbing': '⛰️',
    'kayaking': '🚣',
    'skiing': '⛷️',
  };

  String get emoji => activityEmoji[activityType] ?? '🏕️';
}

class SplitGroup {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final DateTime createdAt;

  const SplitGroup({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
  });

  factory SplitGroup.fromJson(Map<String, dynamic> json) => SplitGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Trip',
        description: json['description'] as String?,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

// A logged trip/group expense. Field shape verified against the LIVE
// split_expenses table (information_schema.columns), which diverges from
// what the repo's own migration file would have produced — this table was
// built through some other, unrecorded path. Two corrections from the
// previous version of this model, both real pre-existing bugs:
//   - the title column is `title`, not `description` — every expense's
//     description silently read as '' before this fix (and SplitsProvider
//     .addExpense's insert below was writing a `description` key that isn't
//     a real column at all, so every add-expense attempt was failing).
//   - `group_id` and `paid_by` are NULLABLE live, not required — fetching a
//     row with either null previously threw a cast exception.
class SplitExpense {
  final String id;

  /// Nullable live (an expense can be trip-linked with no group).
  final String? groupId;

  /// Nullable live — an expense can exist with no recorded payer.
  final String? paidBy;
  final String title;
  final double amount;
  final String currency;
  final DateTime createdAt;

  /// Trip this expense is scoped to, if any — groups (and their older
  /// expenses) can exist with no trip association, so this stays nullable.
  final String? tripId;

  /// One of trip_category_budgets' buckets (stay/food/activity/transit/
  /// shopping/insurance/misc/flights) — same vocabulary as the trip's planned
  /// budget, so actual spend can be compared against it directly.
  final String? category;
  final DateTime? expenseDate;

  /// 'equal' | 'exact' | 'percentage'.
  final String splitType;
  final String? notes;
  final String? receiptUrl;
  final String? createdBy;

  /// True for a balancing payment between members rather than a real
  /// purchase — callers summing spend should exclude these.
  final bool isSettlement;
  final DateTime? updatedAt;

  const SplitExpense({
    required this.id,
    this.groupId,
    this.paidBy,
    required this.title,
    required this.amount,
    required this.currency,
    required this.createdAt,
    this.tripId,
    this.category,
    this.expenseDate,
    this.splitType = 'equal',
    this.notes,
    this.receiptUrl,
    this.createdBy,
    this.isSettlement = false,
    this.updatedAt,
  });

  factory SplitExpense.fromJson(Map<String, dynamic> json) => SplitExpense(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        paidBy: json['paid_by'] as String?,
        title: json['title'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? 'USD',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        tripId: json['trip_id'] as String?,
        category: json['category'] as String?,
        // expense_date is a plain `date` column server-side (no time-of-day),
        // but DateTime.tryParse handles a bare 'YYYY-MM-DD' string fine.
        expenseDate: json['expense_date'] != null
            ? DateTime.tryParse(json['expense_date'] as String)
            : null,
        splitType: json['split_type'] as String? ?? 'equal',
        notes: json['notes'] as String?,
        receiptUrl: json['receipt_url'] as String?,
        createdBy: json['created_by'] as String?,
        isSettlement: json['is_settlement'] as bool? ?? false,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
      );
}

/// One member's share of a [SplitExpense] — real per-member amounts, when
/// they exist. Backs `split_expense_shares`. Nothing writes this table today
/// (SplitsProvider.addExpense only inserts the parent split_expenses row), so
/// in practice this is usually empty for a given expense; [settleUpBalances]
/// falls back to an equal split across trip members when so.
class SplitExpenseShare {
  final String id;
  final String? expenseId;
  final String? userId;
  final double amount;
  final bool isSettled;

  const SplitExpenseShare({
    required this.id,
    this.expenseId,
    this.userId,
    required this.amount,
    this.isSettled = false,
  });

  factory SplitExpenseShare.fromJson(Map<String, dynamic> json) =>
      SplitExpenseShare(
        id: json['id'] as String,
        expenseId: json['expense_id'] as String?,
        userId: json['user_id'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        isSettled: json['is_settled'] as bool? ?? false,
      );
}

/// A recorded payment between two members settling an existing debt — an
/// audit-ledger entry, NOT a derived calculation. Backs `split_settlements`.
/// [settleUpBalances] nets these against the computed balances so a debt
/// someone already paid doesn't keep showing as outstanding.
class SplitSettlement {
  final String id;
  final String? groupId;
  final String? fromUser;
  final String? toUser;
  final double amount;
  final String? note;
  final DateTime? settledAt;
  final String? recordedBy;

  const SplitSettlement({
    required this.id,
    this.groupId,
    this.fromUser,
    this.toUser,
    required this.amount,
    this.note,
    this.settledAt,
    this.recordedBy,
  });

  factory SplitSettlement.fromJson(Map<String, dynamic> json) =>
      SplitSettlement(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        fromUser: json['from_user'] as String?,
        toUser: json['to_user'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        note: json['note'] as String?,
        settledAt: json['settled_at'] != null
            ? DateTime.tryParse(json['settled_at'] as String)
            : null,
        recordedBy: json['recorded_by'] as String?,
      );
}

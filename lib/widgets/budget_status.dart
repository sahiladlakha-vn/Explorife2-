import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Shared budget-state machine. One source of truth for the < 90 / 90–100 / > 100
/// thresholds and their accent colors, consumed by two visuals: the header's
/// [_BudgetPill] (trip_builder_screen.dart) and the sidebar's budget bar
/// (summary_sidebar.dart). Two representations, one state.
///
/// A named class rather than a record so it can grow — e.g. a `formatDelta()`
/// returning "₫5.6M left" / "₫2.1M over" — without breaking call sites.
class BudgetStatus {
  const BudgetStatus._(this.pct, this.over, this.near, this.accent);

  /// Spend as a percentage of budget. 0 when budget is unset (avoids div-by-0).
  final double pct;

  /// Spend exceeds budget.
  final bool over;

  /// Within the 90–100% warning band (never true when [over]).
  final bool near;

  /// Accent for the current band: primary (healthy) / warn / danger.
  final Color accent;

  factory BudgetStatus.of({required int spent, required int budgetVnd}) {
    final pct = budgetVnd > 0 ? spent / budgetVnd * 100 : 0.0;
    final over = pct > 100;
    final near = !over && pct >= 90;
    final accent =
        over ? AppTheme.danger : (near ? AppTheme.warn : AppTheme.primary);
    return BudgetStatus._(pct, over, near, accent);
  }
}

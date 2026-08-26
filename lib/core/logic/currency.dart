// Per-trip currency — the symbol to render, not a conversion system. Every
// money field in this app (budgetVnd, priceVnd, transitCostVnd, amountVnd,
// split-expense amount, …) is stored as a plain integer/whole-unit amount in
// WHATEVER currency the trip is in — there is no exchange-rate conversion
// between trips, and Trip.formatVnd's digit-grouping/short-form logic is
// already currency-agnostic (it never prepended the ₫ glyph itself; callers
// always owned that). This file is the one place that maps a trip's stored
// currency code to the symbol/decimal-convention callers display it with.
class AppCurrency {
  final String code;
  final String symbol;

  /// Informational only (no formatting logic here currently rounds to this) —
  /// callers can use it to decide e.g. whether to show a decimal input step.
  final int decimalDigits;

  /// Dropdown label, e.g. 'VND (₫)'.
  final String label;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.decimalDigits,
    required this.label,
  });
}

/// Curated list for the trip-setup wizard's Currency picker — not the full
/// ISO 4217 set, just the currencies this app's users are likely to plan
/// trips in. VND stays first (the app's original, still-default currency).
const List<AppCurrency> appCurrencies = [
  AppCurrency(code: 'VND', symbol: '₫', decimalDigits: 0, label: 'VND (₫)'),
  AppCurrency(code: 'USD', symbol: '\$', decimalDigits: 2, label: 'USD (\$)'),
  AppCurrency(code: 'EUR', symbol: '€', decimalDigits: 2, label: 'EUR (€)'),
  AppCurrency(code: 'GBP', symbol: '£', decimalDigits: 2, label: 'GBP (£)'),
  AppCurrency(code: 'JPY', symbol: '¥', decimalDigits: 0, label: 'JPY (¥)'),
  AppCurrency(code: 'THB', symbol: '฿', decimalDigits: 2, label: 'THB (฿)'),
  AppCurrency(code: 'SGD', symbol: 'S\$', decimalDigits: 2, label: 'SGD (S\$)'),
  AppCurrency(code: 'AUD', symbol: 'A\$', decimalDigits: 2, label: 'AUD (A\$)'),
];

/// Falls back to VND (the app's original default) for an unrecognized or
/// null code — e.g. a trip created before this feature existed.
AppCurrency currencyFor(String? code) => appCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => appCurrencies.first,
    );

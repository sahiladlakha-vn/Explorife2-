// Regression tests for the per-trip currency lookup (lib/core/logic/
// currency.dart) — the "no conversion, symbol-only" model this session's
// currency feature is built on.

import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/logic/currency.dart';

void main() {
  test('appCurrencies is non-empty and VND is first (the app\'s original '
      'default)', () {
    expect(appCurrencies, isNotEmpty);
    expect(appCurrencies.first.code, 'VND');
  });

  test('every curated currency has a unique code', () {
    final codes = appCurrencies.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length);
  });

  test('currencyFor resolves a known code to the matching entry', () {
    final usd = currencyFor('USD');
    expect(usd.code, 'USD');
    expect(usd.symbol, '\$');
  });

  test('currencyFor falls back to VND for an unknown code', () {
    final result = currencyFor('XXX');
    expect(result.code, 'VND');
    expect(result.symbol, '₫');
  });

  test('currencyFor falls back to VND for a null code (pre-currency-feature '
      'trips)', () {
    final result = currencyFor(null);
    expect(result.code, 'VND');
  });

  test('currencyFor is case-sensitive to the stored wire code (no silent '
      'normalization)', () {
    // Wire codes are always uppercase (from the curated list / DB); a
    // lowercase lookup should NOT accidentally match and should fall back,
    // same as any other unrecognized code.
    final result = currencyFor('usd');
    expect(result.code, 'VND');
  });

  test('label pairs the code with its symbol for the picker sheet', () {
    for (final c in appCurrencies) {
      expect(c.label, contains(c.code));
      expect(c.label, contains(c.symbol));
    }
  });
}

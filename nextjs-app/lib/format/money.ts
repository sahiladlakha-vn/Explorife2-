const COMPACT = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });

/**
 * "15M VND" / "0 VND" — raw currency code suffix rather than a
 * currency-symbol prefix (the Flutter app's `currencyFor(trip.currency)
 * .symbol` lookup has no Next.js equivalent yet). `amountVnd` must already
 * be a `number` — convert `bigint` money fields before calling this.
 */
export function formatCompactMoney(amountVnd: number, currency: string): string {
  return `${COMPACT.format(amountVnd)} ${currency}`;
}

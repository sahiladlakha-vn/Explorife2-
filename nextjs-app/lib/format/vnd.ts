/**
 * Compact Vietnamese money: "1,2 Tỷ đ", "284 tr đ", "950.000 đ".
 *
 * Hand-rolled rather than `Intl.NumberFormat("vi-VN", { notation: "compact" })`
 * — Node's bundled ICU data renders the billions/millions suffixes as "T"/"Tr"
 * (and that output is ICU-build dependent), so the exact label would silently
 * drift between dev and prod. This keeps it deterministic everywhere.
 *
 * Tiers: Tỷ (billion) from 1.000 tr up, tr (million) from 1 tr up, and below a
 * million the full amount grouped with dots (the Vietnamese thousands
 * separator) — "950.000 đ" reads more naturally than a made-up "950 n".
 * The currency suffix ("đ") is part of the result, so callers never append it.
 */
export function formatCompactVnd(amountVnd: number): string {
  const sign = amountVnd < 0 ? "-" : "";
  const abs = Math.abs(amountVnd);

  const billions = abs / 1_000_000_000;
  const millions = abs / 1_000_000;

  // 999.96 tr rounds to "1000 tr" at one decimal — promote it to 1 Tỷ instead.
  if (billions >= 1 || roundOneDecimal(millions) >= 1000) {
    return `${sign}${formatOneDecimal(billions)} Tỷ đ`;
  }
  if (millions >= 1) {
    return `${sign}${formatOneDecimal(millions)} tr đ`;
  }
  return `${sign}${groupThousands(abs)} đ`;
}

function roundOneDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

/** `1.2` -> `"1,2"` (Vietnamese decimal comma), `284.0` -> `"284"` (no trailing `,0`). */
function formatOneDecimal(value: number): string {
  const rounded = roundOneDecimal(value).toFixed(1);
  return rounded.endsWith(".0") ? rounded.slice(0, -2) : rounded.replace(".", ",");
}

/** `950000` -> `"950.000"`. */
function groupThousands(value: number): string {
  return Math.round(value)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

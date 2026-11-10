/**
 * Hand-rolled rather than `Intl.NumberFormat("vi-VN", { notation: "compact" })`
 * — Node's bundled ICU data renders the billions suffix as capitalized "T"
 * (and "Tr" for millions) rather than the lowercase "tỷ"/"tr" the admin
 * dashboard spec asks for, and that output is ICU-data-dependent (varies
 * with the runtime's `full-icu` vs `small-icu` build), which would make the
 * exact label silently drift between dev and prod. This keeps the format
 * deterministic across every environment.
 */
export function formatCompactVnd(amountVnd: number): string {
  const sign = amountVnd < 0 ? "-" : "";
  const abs = Math.abs(amountVnd);

  if (abs >= 1_000_000_000) return `${sign}${formatOneDecimal(abs / 1_000_000_000)} tỷ`;
  if (abs >= 1_000_000) return `${sign}${formatOneDecimal(abs / 1_000_000)} tr`;
  if (abs >= 1_000) return `${sign}${formatOneDecimal(abs / 1_000)} n`;
  return `${sign}${abs}`;
}

/** `1.2` -> `"1,2"` (Vietnamese decimal comma), `284.0` -> `"284"` (no trailing `,0`). */
function formatOneDecimal(value: number): string {
  const rounded = (Math.round(value * 10) / 10).toFixed(1);
  return rounded.endsWith(".0") ? rounded.slice(0, -2) : rounded.replace(".", ",");
}

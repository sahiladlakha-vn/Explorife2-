// Small display formatters for the dashboard. Deterministic on purpose: no
// locale-dependent output, and the only time zone ever applied is Vietnam's.

const vietnamDayFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  timeZone: "Asia/Ho_Chi_Minh",
});

/** "2026-11-21T20:00:00Z" -> "Nov 22": the Vietnam calendar day of an instant (UTC+7). */
export function vietnamDayShort(iso: string): string {
  return vietnamDayFormatter.format(new Date(iso));
}

function oneDecimal(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/** Average verification time in the most readable unit: "45 min", "4.3 h", "2.5 d". */
export function formatTurnaround(hours: number): string {
  if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} min`;
  if (hours < 48) return `${oneDecimal(hours)} h`;
  return `${oneDecimal(hours / 24)} d`;
}

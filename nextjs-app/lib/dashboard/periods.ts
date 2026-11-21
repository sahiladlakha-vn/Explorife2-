// Performance Overview toggle (Month / Quarter / Year). Plain values only — no
// `server-only` — because both the server queries and the client toggle use them.
//
// Windows are rolling day counts back from now, not calendar months: "Quarter"
// is the same 90-day window the Top Destinations card has always used.
export type PerformancePeriod = "month" | "quarter" | "year";

export const PERFORMANCE_PERIODS: readonly PerformancePeriod[] = [
  "month",
  "quarter",
  "year",
];

export const PERFORMANCE_PERIOD_DAYS: Record<PerformancePeriod, number> = {
  month: 30,
  quarter: 90,
  year: 365,
};

export const PERFORMANCE_PERIOD_LABEL: Record<PerformancePeriod, string> = {
  month: "Month",
  quarter: "Quarter",
  year: "Year",
};

export const DEFAULT_PERFORMANCE_PERIOD: PerformancePeriod = "quarter";

/** Phrase for empty states, e.g. "in the last 30 days". */
export function periodWindowPhrase(period: PerformancePeriod): string {
  return `in the last ${PERFORMANCE_PERIOD_DAYS[period]} days`;
}

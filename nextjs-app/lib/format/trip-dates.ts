const MONTH = new Intl.DateTimeFormat("en-US", { month: "short", timeZone: "UTC" });

/**
 * "Aug 12 – 22 · 10 nights" (same month), "Aug 28 – Sep 2 · 5 nights" (cross
 * month), or "Dec 29, 2026 – Jan 2, 2027 · 4 nights" (cross year). Dates are
 * `@db.Date` columns, read back by Prisma as UTC-midnight `Date`s — formatted
 * in UTC here so the displayed day-of-month never shifts with the viewer's
 * local timezone.
 */
export function formatTripDateRange(start: Date, end: Date): string {
  const nights = Math.round((end.getTime() - start.getTime()) / 86_400_000);
  const nightsLabel = `${nights} night${nights === 1 ? "" : "s"}`;

  const startYear = start.getUTCFullYear();
  const endYear = end.getUTCFullYear();
  const startDay = start.getUTCDate();
  const endDay = end.getUTCDate();
  const startMonth = MONTH.format(start);
  const endMonth = MONTH.format(end);

  let range: string;
  if (startYear !== endYear) {
    range = `${startMonth} ${startDay}, ${startYear} – ${endMonth} ${endDay}, ${endYear}`;
  } else if (startMonth !== endMonth) {
    range = `${startMonth} ${startDay} – ${endMonth} ${endDay}`;
  } else {
    range = `${startMonth} ${startDay} – ${endDay}`;
  }

  return `${range} · ${nightsLabel}`;
}

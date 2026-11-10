import type { DocumentType } from "./document-type";

/**
 * Ports trips_tab.dart's `_expiryAlertFor`/`_fmtDocDate`/`_months` (lines
 * 843-884) — pure trip-document-expiry business logic, split out of
 * DocumentsCard.tsx for the same reason document-type.ts is its own module:
 * no "use client"/"server-only" dependency, unit-testable in isolation
 * (document-alerts.test.ts).
 *
 * `_months` itself isn't ported as a literal array — `Intl.DateTimeFormat`
 * with `month: "short"` produces the identical "Jan".."Dec" strings, the
 * same approach lib/format/trip-dates.ts's own `MONTH` formatter already
 * uses for the same reason (and the same `timeZone: "UTC"` rationale below).
 */
const MONTH = new Intl.DateTimeFormat("en-US", { month: "short", timeZone: "UTC" });

/**
 * Mirrors `_fmtDocDate` — e.g. "Aug 12, 2026". `d` is a `@db.Date` column,
 * read back by Prisma as a UTC-midnight `Date` (see trip-dates.ts's own
 * note), so components are read in UTC rather than the viewer's local
 * timezone — otherwise the displayed day-of-month could shift by one.
 */
export function formatDocumentDate(d: Date): string {
  return `${MONTH.format(d)} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

export type DocumentExpiryAlert = { label: string; tone: "critical" | "warn" };

/**
 * Mirrors `_expiryAlertFor` exactly, including its exhaustiveness note: a
 * passport clearing the 6-month-after-trip-end bar is, by construction,
 * already outside the trip's own date window, so the two branches below
 * never both fire for the same document — evaluated in severity order
 * (critical, then warn) same as the Dart original.
 *
 * `Date.UTC`'s month argument rolls over just like Dart's `DateTime`
 * constructor does (month 13 -> January of the following year), so
 * `endDate`'s month + 6 overflowing past December is handled the same way
 * here as it is there, with no special-casing needed.
 */
export function expiryAlertFor(
  doc: { type: DocumentType; expiresOn: Date | null },
  trip: { startDate: Date; endDate: Date },
): DocumentExpiryAlert | null {
  const { expiresOn } = doc;
  if (!expiresOn) return null;

  if (doc.type === "passport") {
    const sixMoAfterEnd = Date.UTC(
      trip.endDate.getUTCFullYear(),
      trip.endDate.getUTCMonth() + 6,
      trip.endDate.getUTCDate(),
    );
    if (expiresOn.getTime() < sixMoAfterEnd) {
      return { label: "6-MO RULE", tone: "critical" };
    }
  }

  const start = Date.UTC(trip.startDate.getUTCFullYear(), trip.startDate.getUTCMonth(), trip.startDate.getUTCDate());
  const end = Date.UTC(trip.endDate.getUTCFullYear(), trip.endDate.getUTCMonth(), trip.endDate.getUTCDate());
  const expiry = Date.UTC(expiresOn.getUTCFullYear(), expiresOn.getUTCMonth(), expiresOn.getUTCDate());
  if (expiry >= start && expiry <= end) {
    return { label: "ENDS MID-TRIP", tone: "warn" };
  }
  return null;
}

// Universal (no "server-only"/"use client" directive) trip-document-type
// domain module — mirrors lib/models/trip_document.dart's `DocumentType`
// enum. Deliberately split out of lib/server/trip-setup.ts (which IS
// server-only) so that Client Components rendering the "Add document" type
// chips can import these value bindings directly, the same way
// lib/format/trip-dates.ts is a plain shared module already imported by the
// client component TripSwitcher.tsx. Only type-only imports are safe from a
// server-only module (erased at compile time); DOCUMENT_TYPES/
// documentTypeLabel are runtime values, so they need a home outside it.

/** Wire values match the live `trip_documents.type` CHECK constraint exactly. */
export type DocumentType = "passport" | "visa" | "ticket" | "reservation" | "insurance";

/** Declaration order mirrors Dart's `DocumentType.values` (used to render the "Add document" type chips in that order). */
export const DOCUMENT_TYPES: readonly DocumentType[] = [
  "passport",
  "visa",
  "ticket",
  "reservation",
  "insurance",
];

const DOCUMENT_TYPE_LABELS: Record<DocumentType, string> = {
  passport: "Passport",
  visa: "Visa",
  ticket: "Ticket",
  reservation: "Reservation",
  insurance: "Insurance",
};

export function isDocumentType(value: string): value is DocumentType {
  return Object.hasOwn(DOCUMENT_TYPE_LABELS, value);
}

/**
 * Mirrors `DocumentType.fromWire`: a deliberate silent fallback to
 * "reservation" for any value outside the live CHECK constraint's domain
 * (only possible via a future migration widening it ahead of this code).
 */
export function normalizeDocumentType(value: string | null | undefined): DocumentType {
  return value != null && isDocumentType(value) ? value : "reservation";
}

/** Mirrors trips_tab.dart's `_documentTypeLabel`. Accepts a raw, not-yet-normalized wire value so callers can label a value straight off the wire. */
export function documentTypeLabel(value: string): string {
  return DOCUMENT_TYPE_LABELS[normalizeDocumentType(value)];
}

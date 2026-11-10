/**
 * Minimal hand-rolled icon set (no icon library is installed yet — see
 * MIGRATION_PLAN.md §7 Step 4 proposal). Each is a plain inline SVG so the
 * trip header/switcher don't need a new dependency for four glyphs.
 */

type IconProps = { className?: string };

export function ChevronDownIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path
        d="M5 7.5L10 12.5L15 7.5"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function CalendarIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <rect x="3" y="4.5" width="14" height="12" rx="2" stroke="currentColor" strokeWidth="1.5" />
      <path d="M3 8.5H17" stroke="currentColor" strokeWidth="1.5" />
      <path d="M6.5 2.5V5.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M13.5 2.5V5.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function PlusIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path d="M10 4V16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M4 10H16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function CheckIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path
        d="M4 10.5L8 14.5L16 6"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/** Standard multi-color Google "G" mark — used on the `/auth` sign-in buttons. */
export function GoogleIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" aria-hidden="true" className={className}>
      <path
        d="M19.6 10.23c0-.68-.06-1.33-.17-1.96H10v3.71h5.38a4.6 4.6 0 01-2 3.02v2.5h3.23c1.89-1.74 2.98-4.3 2.98-7.27z"
        fill="#4285F4"
      />
      <path
        d="M10 20c2.7 0 4.96-.9 6.62-2.43l-3.23-2.5c-.9.6-2.05.96-3.39.96-2.6 0-4.8-1.76-5.59-4.12H1.07v2.59A10 10 0 0010 20z"
        fill="#34A853"
      />
      <path
        d="M4.41 11.9A6 6 0 014.09 10c0-.66.11-1.3.32-1.9V5.51H1.07a10 10 0 000 8.98l3.34-2.59z"
        fill="#FBBC05"
      />
      <path
        d="M10 3.98c1.47 0 2.79.5 3.82 1.49l2.87-2.87C14.95.99 12.7 0 10 0A10 10 0 001.07 5.51l3.34 2.6C5.2 5.75 7.4 3.98 10 3.98z"
        fill="#EA4335"
      />
    </svg>
  );
}

/** Standard GitHub "octocat" mark, single-color so it follows `currentColor`. */
export function GitHubIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" className={className}>
      <path d="M10 0C4.48 0 0 4.59 0 10.25c0 4.53 2.87 8.37 6.84 9.73.5.1.68-.22.68-.49 0-.24-.01-1.04-.01-1.88-2.78.61-3.37-1.21-3.37-1.21-.46-1.18-1.11-1.5-1.11-1.5-.91-.63.07-.62.07-.62 1 .07 1.53 1.05 1.53 1.05.89 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05a9.3 9.3 0 015.01 0c1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.95.68 1.92 0 1.39-.01 2.51-.01 2.85 0 .27.18.6.69.49A10.26 10.26 0 0020 10.25C20 4.59 15.52 0 10 0z" />
    </svg>
  );
}

/*
 * Trip screen icon set (components/features/trips/{Travelers,Documents,
 * Packing}Card.tsx + TravelerLookupSheet.tsx) — same hand-drawn-approximation
 * approach as the icons above, loosely matching the Material glyph each
 * replaces rather than reproducing its exact path:
 *   GroupsIcon      ~ Icons.groups_outlined            (Travelers card header)
 *   DocumentIcon    ~ Icons.description_outlined        (Documents card header + empty state)
 *   ChecklistIcon   ~ Icons.checklist_outlined          (Packing card header + empty state)
 *   CloseIcon       ~ Icons.close                       (remove document/packing row)
 *   CheckCircleIcon ~ Icons.check_circle(_rounded)      (packed toggle ON; lookup result check)
 *   CircleIcon      ~ Icons.radio_button_unchecked_rounded (packed toggle OFF)
 *   MinusIcon       ~ Icons.remove                      (quantity stepper −; PlusIcon above already covers +)
 *   SearchIcon      ~ Icons.search                      (lookup search field; also stands in for
 *                                                         Icons.person_search_outlined's "not found" message —
 *                                                         a dedicated person+magnifier glyph isn't worth a 10th icon)
 *   InfoCircleIcon  ~ Icons.info_outline                (lookup "that's you" message)
 * `check_circle_outline` (lookup "already added" message) also reuses
 * CheckCircleIcon: it's drawn as a true even-odd cutout (not an overlaid
 * stroke), so the checkmark always shows whatever is behind it — correct on
 * both the dark packing card and the light lookup sheet without a prop.
 */

export function GroupsIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <circle cx="7.2" cy="6.8" r="2.3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="13.3" cy="7.3" r="2" stroke="currentColor" strokeWidth="1.5" />
      <path
        d="M2.5 16.2c0-2.76 2.1-4.7 4.7-4.7s4.7 1.94 4.7 4.7"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <path d="M12.3 12.1c2.1.3 3.7 2 3.7 4.1" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function DocumentIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path
        d="M6 2.5h5.5L16 7v9.5a1 1 0 01-1 1H6a1 1 0 01-1-1v-13a1 1 0 011-1z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <path d="M11.5 2.5V7H16" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M7.5 10.5h5M7.5 13.5h5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function ChecklistIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path
        d="M3.5 5.2l1.3 1.3L7 4.2"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M9.5 5h7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path
        d="M3.5 10.2l1.3 1.3L7 9.2"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M9.5 10h7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path
        d="M3.5 15.2l1.3 1.3L7 14.2"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M9.5 15h7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function CloseIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path d="M5 5L15 15M15 5L5 15" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Solid circle with the checkmark cut out via `evenodd` (a true hole, not an overlaid stroke) — see file-header note above. */
export function CheckCircleIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" className={className}>
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm3.8-10.4a.9.9 0 0 0-1.33-1.2l-4.2 4.63-1.77-1.77a.9.9 0 1 0-1.27 1.27l2.45 2.45a.9.9 0 0 0 1.3-.03l4.82-5.35Z"
      />
    </svg>
  );
}

export function CircleIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <circle cx="10" cy="10" r="7.25" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

export function MinusIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <path d="M4 10H16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function SearchIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <circle cx="8.5" cy="8.5" r="5.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M16.5 16.5L13 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

export function InfoCircleIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className={className}>
      <circle cx="10" cy="10" r="7.25" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10 9.25V14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <circle cx="10" cy="6.75" r="0.9" fill="currentColor" />
    </svg>
  );
}

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

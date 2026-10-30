import "server-only";
import { getSiteUrl } from "./site-url";

/** Landing page when no valid `?redirect=` was supplied. */
export const DEFAULT_REDIRECT = "/profile/overview";

// Matches ASCII control characters (tabs, newlines, etc.) smuggled into the
// query string — a classic trick for sneaking a "javascript:"-like value
// past a naive prefix check.
const CONTROL_CHARS = /[\x00-\x1f\x7f]/;

/**
 * `?redirect=` is attacker-controlled (a crafted sign-in link), so only a
 * same-origin relative path is ever followed — reject protocol-relative
 * URLs ("//evil.com"), absolute URLs, backslash tricks ("/\evil.com", which
 * some browsers normalize to "//evil.com"), control characters, and a
 * leading path segment containing a colon (e.g. "/javascript:alert(1)").
 * Falls back to `/profile/overview` for anything that doesn't pass.
 */
export function sanitizeRedirect(value: string | null | undefined): string {
  if (!value) return DEFAULT_REDIRECT;
  if (CONTROL_CHARS.test(value)) return DEFAULT_REDIRECT;
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) {
    return DEFAULT_REDIRECT;
  }

  const firstSegment = value.slice(1).split("/")[0] ?? "";
  if (firstSegment.includes(":")) return DEFAULT_REDIRECT;

  const siteUrl = getSiteUrl();
  let resolved: URL;
  try {
    resolved = new URL(value, siteUrl);
  } catch {
    return DEFAULT_REDIRECT;
  }

  if (resolved.origin !== new URL(siteUrl).origin) {
    return DEFAULT_REDIRECT;
  }

  return `${resolved.pathname}${resolved.search}${resolved.hash}`;
}

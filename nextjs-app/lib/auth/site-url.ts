import "server-only";

/**
 * Always build OAuth/callback redirect URLs from this, never from a
 * request's Host header — a misconfigured/unprotected proxy can forge that
 * header, which would otherwise let an attacker redirect the OAuth flow
 * (and its `code`) to a host they control.
 */
export function getSiteUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
}

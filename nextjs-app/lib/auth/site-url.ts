import "server-only";

/**
 * Always build OAuth/callback redirect URLs from this, never from a
 * request's Host header — a misconfigured/unprotected proxy can forge that
 * header, which would otherwise let an attacker redirect the OAuth flow
 * (and its `code`) to a host they control.
 *
 * Falls back to Vercel's per-deployment `VERCEL_URL` (unset locally) so
 * Preview deployments — which don't have a fixed domain to put in
 * `NEXT_PUBLIC_SITE_URL` — still resolve to their own URL instead of
 * localhost. Production should keep `NEXT_PUBLIC_SITE_URL` set explicitly
 * to its stable custom domain rather than relying on this.
 */
export function getSiteUrl(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL;
  }
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }
  return "http://localhost:3000";
}

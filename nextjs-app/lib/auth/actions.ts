"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSiteUrl } from "./site-url";
import { sanitizeRedirect, DEFAULT_REDIRECT } from "./redirect";

export type OAuthProvider = "google" | "github";

function isOAuthProvider(value: FormDataEntryValue | null): value is OAuthProvider {
  return value === "google" || value === "github";
}

/**
 * The URL `/auth/callback/route.ts` reads back. Carries the sanitized
 * post-login destination AND the provider through the entire OAuth round
 * trip as our own query params — not GoTrue's — since we need both even on
 * GoTrue's failure redirects (to show "Sign in with this {provider} account"
 * for `identity_already_exists`), not just on success. Always built from
 * `getSiteUrl()`, never the request's own Host header, so this can't be
 * turned into an open redirect by a forged/unprotected proxy header.
 */
function callbackUrl(provider: OAuthProvider, redirectPath: string): string {
  const params = new URLSearchParams({
    redirect: sanitizeRedirect(redirectPath),
    provider,
  });
  return `${getSiteUrl()}/auth/callback?${params.toString()}`;
}

/** Where `/auth` itself shows a failure that happened before any provider redirect even fired. */
function authInitErrorUrl(redirectPath: string): string {
  const params = new URLSearchParams({
    redirect: sanitizeRedirect(redirectPath),
    error: "server_error",
  });
  return `/auth?${params.toString()}`;
}

/**
 * Starts an OAuth sign-in. Ports the three cases in AuthProvider's
 * `signInWithGoogle`/`signInWithGoogleDirect`/`signInWithGitHub`
 * (lib/providers/auth_provider.dart), generalized to both providers — the
 * Step 5 proposal explicitly does NOT carry over Flutter's Google-only
 * linking asymmetry:
 *
 * - `direct: true` (the `identity_already_exists` recovery action) — always
 *   a plain sign-in, bypassing linking even if the current session is a
 *   guest. Signs straight into whichever account already owns that
 *   identity; the current guest session's data is not merged into it (same
 *   tradeoff `signInWithGoogleDirect` documents).
 * - current session is a guest (anonymous) and not `direct` — `linkIdentity`,
 *   which keeps the same `auth.uid()` so existing guest data carries over.
 * - otherwise (no session, or already a real session) — plain `signInWithOAuth`.
 */
export async function signInWithProvider(
  provider: OAuthProvider,
  redirectPath: string,
  direct = false,
): Promise<void> {
  const supabase = await createClient();
  const redirectTo = callbackUrl(provider, redirectPath);

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const isGuestLinking = !direct && user?.is_anonymous === true;

  const { data, error } = isGuestLinking
    ? await supabase.auth.linkIdentity({ provider, options: { redirectTo } })
    : await supabase.auth.signInWithOAuth({ provider, options: { redirectTo } });

  if (error || !data?.url) {
    redirect(authInitErrorUrl(redirectPath));
  }

  redirect(data.url);
}

/**
 * FormData adapter for `<form action={signInAction}>` — reads
 * `provider`/`redirect`/`direct` hidden fields rather than relying on
 * `Function.prototype.bind`, so the page component stays a plain Server
 * Component (no client-side event handler needed to call a bound action).
 */
export async function signInAction(formData: FormData): Promise<void> {
  const provider = formData.get("provider");
  const redirectPath = formData.get("redirect")?.toString() ?? DEFAULT_REDIRECT;

  if (!isOAuthProvider(provider)) {
    redirect(authInitErrorUrl(redirectPath));
  }

  const direct = formData.get("direct")?.toString() === "true";
  return signInWithProvider(provider, redirectPath, direct);
}

/**
 * Signs out. An anonymous/guest session has no account to come back to, so
 * the caller MUST have already shown the visitor a confirmation explaining
 * their guest data will be permanently lost (see `app/auth/sign-out/page.tsx`)
 * before setting `confirmed: true` — it defaults to `false` so this can never
 * silently drop a guest's data on a stray call.
 */
export async function signOutAction(formData: FormData): Promise<void> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const confirmed = formData.get("confirmed")?.toString() === "true";
  if (user?.is_anonymous && !confirmed) {
    throw new Error("Guest sign-out requires confirmation.");
  }

  await supabase.auth.signOut();
  redirect("/");
}

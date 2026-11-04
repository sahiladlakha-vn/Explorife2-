import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getSiteUrl } from "@/lib/auth/site-url";
import { sanitizeRedirect } from "@/lib/auth/redirect";

/**
 * Always resolved against `getSiteUrl()`, never `request.url`'s own origin
 * (which can be forged by an unprotected proxy's Host header, same reasoning
 * as `getSiteUrl()`'s own doc comment) — this route only ever needs to issue
 * redirects back to this app, never anywhere else.
 */
function absoluteUrl(pathAndQuery: string): URL {
  return new URL(pathAndQuery, getSiteUrl());
}

/**
 * Builds the `/auth` failure URL — carries `redirect` (so the user doesn't
 * lose their original destination) and `error` (our own normalized code,
 * fed through `friendlyAuthErrorMessage` on `/auth`) and `provider` (so
 * `identity_already_exists` can offer "sign in with this {provider} account"
 * directly). Deliberately never forwards GoTrue's raw `error_description`.
 */
function authErrorUrl(redirectTo: string, errorCode: string, provider: string | null): URL {
  const params = new URLSearchParams({ redirect: redirectTo, error: errorCode });
  if (provider) params.set("provider", provider);
  return absoluteUrl(`/auth?${params.toString()}`);
}

/**
 * Landing page for both `signInWithOAuth` and `linkIdentity` redirects
 * (lib/auth/actions.ts's `callbackUrl`). Two distinct failure shapes exist:
 *
 * - GoTrue rejects the attempt before ever issuing a code (e.g. the Google
 *   account picked is already linked to a different real account) — it
 *   redirects straight back here with `error`/`error_code`/`error_description`
 *   and no `code` at all.
 * - A `code` arrives and `exchangeCodeForSession` itself fails (expired/
 *   reused code, network blip, etc).
 *
 * Both land on the same `/auth?error=...` shape so `/auth` shows one
 * consistent error UI either way.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const errorCode = url.searchParams.get("error_code") ?? url.searchParams.get("error");
  const provider = url.searchParams.get("provider");
  const redirectTo = sanitizeRedirect(url.searchParams.get("redirect"));

  if (errorCode) {
    return NextResponse.redirect(authErrorUrl(redirectTo, errorCode, provider));
  }

  if (!code) {
    return NextResponse.redirect(authErrorUrl(redirectTo, "server_error", provider));
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(authErrorUrl(redirectTo, "server_error", provider));
  }

  return NextResponse.redirect(absoluteUrl(redirectTo));
}

/**
 * Fixed, pre-written copy for GoTrue's `error`/`error_code` redirect params —
 * ported from the Flutter app's `_friendlyAuthError` (lib/core/router/
 * app_router.dart). `error_description` (GoTrue's free-text explanation) is
 * deliberately never read into this module or rendered anywhere: it rides
 * through the same redirect URL as `code`, so it's exactly as
 * attacker-influenced as any other query param, and echoing attacker-
 * controlled text back into the page is a reflected-XSS-shaped risk this
 * app doesn't need to take on for what is, worst case, a wrong sign-in
 * error message. Unknown codes get one generic, safe fallback instead.
 */

export const IDENTITY_ALREADY_EXISTS = "identity_already_exists";

const GENERIC_AUTH_ERROR_MESSAGE = "Sign-in failed. Please try again.";

const AUTH_ERROR_MESSAGES: Readonly<Record<string, string>> = {
  [IDENTITY_ALREADY_EXISTS]:
    "That account is already linked to a different Explorife profile. Try a different account, or sign in with that account directly below.",
  access_denied: "Sign-in was cancelled.",
  server_error: "The sign-in provider had a problem. Please try again.",
  otp_expired: "That sign-in link expired. Please try again.",
};

/**
 * Maps a known GoTrue error code to its fixed message; any other value
 * (including `null`/`undefined`) gets the generic fallback. Never pass
 * `error_description` here — this function only ever returns one of the
 * fixed strings above, by design.
 */
export function friendlyAuthErrorMessage(code: string | null | undefined): string {
  if (!code) return GENERIC_AUTH_ERROR_MESSAGE;
  return AUTH_ERROR_MESSAGES[code] ?? GENERIC_AUTH_ERROR_MESSAGE;
}
